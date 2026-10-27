import pyodbc
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from database.connection import get_connection

router = APIRouter(prefix="/results", tags=["Results"])


class StartExamRequest(BaseModel):
    user_id: int = Field(gt=0)
    topic_id: int = Field(gt=0)
    question_ids: list[int] = Field(min_length=1, max_length=200)


class SubmittedAnswer(BaseModel):
    question_id: int = Field(gt=0)
    selected_option_id: int | None = Field(default=None, gt=0)


class CompleteExamRequest(BaseModel):
    user_id: int = Field(gt=0)
    duration_seconds: int = Field(ge=0)
    answers: list[SubmittedAnswer] = Field(min_length=1, max_length=200)


class ResultReleaseUpdate(BaseModel):
    is_released: bool


@router.post("/start", status_code=201)
def start_exam(request: StartExamRequest):
    if len(set(request.question_ids)) != len(request.question_ids):
        raise HTTPException(
            status_code=400,
            detail="Question IDs must be unique."
        )
    if any(question_id <= 0 for question_id in request.question_ids):
        raise HTTPException(
            status_code=400,
            detail="Question IDs must be positive."
        )

    connection = get_connection()

    try:
        cursor = connection.cursor()
        cursor.execute("SET TRANSACTION ISOLATION LEVEL SERIALIZABLE")

        cursor.execute(
            "SELECT UserId FROM dbo.Users WHERE UserId = ?",
            request.user_id
        )
        if cursor.fetchone() is None:
            raise HTTPException(status_code=404, detail="Student not found.")

        cursor.execute(
            """
            SELECT TopicName
            FROM dbo.Topics
            WHERE TopicId = ? AND IsActive = 1 AND IsDeleted = 0
            """,
            request.topic_id
        )
        topic = cursor.fetchone()
        if topic is None:
            raise HTTPException(status_code=404, detail="Topic not found.")

        placeholders = ", ".join("?" for _ in request.question_ids)
        cursor.execute(
            f"""
            SELECT QuestionId
            FROM dbo.Questions
            WHERE TopicId = ? AND IsActive = 1
                AND QuestionId IN ({placeholders})
            """,
            request.topic_id,
            *request.question_ids
        )
        valid_question_ids = {row.QuestionId for row in cursor.fetchall()}
        if valid_question_ids != set(request.question_ids):
            raise HTTPException(
                status_code=400,
                detail="One or more exam questions are invalid or inactive."
            )

        cursor.execute(
            """
            SELECT TOP 1 ExamId
            FROM dbo.Exams WITH (UPDLOCK, HOLDLOCK)
            WHERE TopicId = ? AND IsActive = 1
            ORDER BY ExamId
            """,
            request.topic_id
        )
        exam = cursor.fetchone()

        if exam is None:
            exam_name = f"{topic.TopicName} Quiz"[:150]
            cursor.execute(
                """
                INSERT INTO dbo.Exams
                    (TopicId, ExamName, DurationMinutes, TotalQuestions, PassMark)
                OUTPUT INSERTED.ExamId
                VALUES (?, ?, 5, ?, 50)
                """,
                request.topic_id,
                exam_name,
                len(request.question_ids)
            )
            exam_id = cursor.fetchone().ExamId
        else:
            exam_id = exam.ExamId
            cursor.execute(
                """
                UPDATE dbo.Exams
                SET TotalQuestions = ?
                WHERE ExamId = ?
                """,
                len(request.question_ids),
                exam_id
            )

        cursor.execute(
            "SELECT QuestionId FROM dbo.ExamQuestions WHERE ExamId = ?",
            exam_id
        )
        exam_question_ids = {row.QuestionId for row in cursor.fetchall()}
        next_order = 0
        cursor.execute(
            """
            SELECT COALESCE(MAX(QuestionOrder), 0)
            FROM dbo.ExamQuestions
            WHERE ExamId = ?
            """,
            exam_id
        )
        next_order = cursor.fetchone()[0]

        for question_id in request.question_ids:
            if question_id not in exam_question_ids:
                next_order += 1
                cursor.execute(
                    """
                    INSERT INTO dbo.ExamQuestions
                        (ExamId, QuestionId, QuestionOrder)
                    VALUES (?, ?, ?)
                    """,
                    exam_id,
                    question_id,
                    next_order
                )

        cursor.execute(
            """
            INSERT INTO dbo.ExamResults
                (UserId, ExamId, Score, TotalQuestions, Status)
            OUTPUT INSERTED.ResultId
            VALUES (?, ?, 0, ?, 'InProgress')
            """,
            request.user_id,
            exam_id,
            len(request.question_ids)
        )
        result_id = cursor.fetchone().ResultId
        connection.commit()
        return {"result_id": result_id, "exam_id": exam_id}

    except HTTPException:
        connection.rollback()
        raise
    except pyodbc.Error as exc:
        connection.rollback()
        print("Start exam database error:", exc)
        raise HTTPException(
            status_code=500,
            detail="Failed to start and record the exam."
        ) from exc
    finally:
        connection.close()


@router.post("/{result_id}/complete")
def complete_exam(result_id: int, request: CompleteExamRequest):
    if result_id <= 0:
        raise HTTPException(status_code=400, detail="Invalid result ID.")

    question_ids = [answer.question_id for answer in request.answers]
    if len(set(question_ids)) != len(question_ids):
        raise HTTPException(
            status_code=400,
            detail="Each exam question may only be submitted once."
        )

    connection = get_connection()

    try:
        cursor = connection.cursor()
        cursor.execute("SET TRANSACTION ISOLATION LEVEL SERIALIZABLE")
        cursor.execute(
            """
            SELECT UserId, ExamId, Score, TotalQuestions, Status
            FROM dbo.ExamResults WITH (UPDLOCK, ROWLOCK)
            WHERE ResultId = ?
            """,
            result_id
        )
        result = cursor.fetchone()
        if result is None:
            raise HTTPException(status_code=404, detail="Exam result not found.")
        if result.UserId != request.user_id:
            raise HTTPException(
                status_code=403,
                detail="This exam result belongs to another student."
            )
        if result.Status == "Completed":
            return {
                "result_id": result_id,
                "status": result.Status,
                "message": "Exam result submitted and is awaiting release."
            }
        if result.Status != "InProgress":
            raise HTTPException(
                status_code=409,
                detail="This exam attempt cannot be completed."
            )
        if len(request.answers) != result.TotalQuestions:
            raise HTTPException(
                status_code=400,
                detail="Submitted answers do not match the exam question count."
            )

        placeholders = ", ".join("?" for _ in question_ids)
        cursor.execute(
            f"""
            SELECT questions.QuestionId, options.OptionId, options.IsCorrect
            FROM dbo.ExamQuestions AS exam_questions
            INNER JOIN dbo.Questions AS questions
                ON questions.QuestionId = exam_questions.QuestionId
            LEFT JOIN dbo.QuestionOptions AS options
                ON options.QuestionId = questions.QuestionId
            WHERE exam_questions.ExamId = ?
                AND questions.QuestionId IN ({placeholders})
            """,
            result.ExamId,
            *question_ids
        )

        valid_questions: set[int] = set()
        options_by_question: dict[int, dict[int, bool]] = {}
        for row in cursor.fetchall():
            valid_questions.add(row.QuestionId)
            if row.OptionId is not None:
                options_by_question.setdefault(row.QuestionId, {})[
                    row.OptionId
                ] = bool(row.IsCorrect)

        if valid_questions != set(question_ids):
            raise HTTPException(
                status_code=400,
                detail="Submitted questions do not belong to this exam."
            )

        score = 0
        for answer in request.answers:
            question_options = options_by_question.get(answer.question_id, {})
            if (
                answer.selected_option_id is not None
                and answer.selected_option_id not in question_options
            ):
                raise HTTPException(
                    status_code=400,
                    detail="A selected option does not belong to its question."
                )

            is_correct = bool(
                answer.selected_option_id is not None
                and question_options.get(answer.selected_option_id, False)
            )
            score += int(is_correct)
            cursor.execute(
                """
                INSERT INTO dbo.StudentAnswers
                    (ResultId, QuestionId, SelectedOptionId, IsCorrect, AnsweredAt)
                VALUES (?, ?, ?, ?, SYSDATETIME())
                """,
                result_id,
                answer.question_id,
                answer.selected_option_id,
                is_correct
            )

        cursor.execute(
            """
            UPDATE dbo.ExamResults
            SET Score = ?, CompletedAt = SYSDATETIME(),
                DurationSeconds = ?, Status = 'Completed'
            WHERE ResultId = ? AND Status = 'InProgress'
            """,
            score,
            request.duration_seconds,
            result_id
        )
        connection.commit()

        return {
            "result_id": result_id,
            "status": "Completed",
            "message": "Exam result submitted and is awaiting release."
        }

    except HTTPException:
        connection.rollback()
        raise
    except pyodbc.Error as exc:
        connection.rollback()
        print("Complete exam database error:", exc)
        raise HTTPException(
            status_code=500,
            detail="Failed to save the exam result."
        ) from exc
    finally:
        connection.close()


@router.get("/{result_id}/student")
def get_student_result(result_id: int, user_id: int):
    if result_id <= 0 or user_id <= 0:
        raise HTTPException(status_code=400, detail="Invalid result request.")

    connection = get_connection()

    try:
        cursor = connection.cursor()
        cursor.execute(
            """
            SELECT
                result.ResultId,
                result.UserId,
                result.Score,
                result.TotalQuestions,
                result.Status,
                result.IsReleased,
                exams.PassMark
            FROM dbo.ExamResults AS result
            INNER JOIN dbo.Exams AS exams
                ON exams.ExamId = result.ExamId
            WHERE result.ResultId = ? AND result.UserId = ?
            """,
            result_id,
            user_id
        )
        result = cursor.fetchone()
        if result is None:
            raise HTTPException(status_code=404, detail="Exam result not found.")

        if result.Status != "Completed":
            return {
                "result_id": result.ResultId,
                "status": result.Status,
                "is_released": False
            }

        if not result.IsReleased:
            return {
                "result_id": result.ResultId,
                "status": result.Status,
                "is_released": False,
                "message": "Your result is waiting for admin approval."
            }

        percentage = result.Score * 100 / result.TotalQuestions
        return {
            "result_id": result.ResultId,
            "status": result.Status,
            "is_released": True,
            "score": result.Score,
            "total_questions": result.TotalQuestions,
            "percentage": percentage,
            "pass_mark": float(result.PassMark),
            "passed": percentage >= float(result.PassMark)
        }

    except HTTPException:
        raise
    except pyodbc.Error as exc:
        print("Get student result database error:", exc)
        raise HTTPException(
            status_code=500,
            detail="Failed to retrieve the student result."
        ) from exc
    finally:
        connection.close()


@router.patch("/{result_id}/release")
def release_student_result(
    result_id: int,
    request: ResultReleaseUpdate
):
    if result_id <= 0:
        raise HTTPException(status_code=400, detail="Invalid result ID.")

    connection = get_connection()

    try:
        cursor = connection.cursor()
        cursor.execute(
            """
            SELECT Status
            FROM dbo.ExamResults
            WHERE ResultId = ?
            """,
            result_id
        )
        result = cursor.fetchone()
        if result is None:
            raise HTTPException(status_code=404, detail="Exam result not found.")
        if result.Status != "Completed":
            raise HTTPException(
                status_code=409,
                detail="Only completed exam results can be released."
            )

        cursor.execute(
            """
            UPDATE dbo.ExamResults
            SET IsReleased = ?
            WHERE ResultId = ? AND Status = 'Completed'
            """,
            request.is_released,
            result_id
        )
        connection.commit()
        return {
            "result_id": result_id,
            "is_released": request.is_released,
            "message": (
                "Result released to the student."
                if request.is_released
                else "Result hidden from the student."
            )
        }

    except HTTPException:
        connection.rollback()
        raise
    except pyodbc.Error as exc:
        connection.rollback()
        print("Release exam result database error:", exc)
        raise HTTPException(
            status_code=500,
            detail="Failed to update result release status."
        ) from exc
    finally:
        connection.close()


class AbandonExamRequest(BaseModel):
    user_id: int = Field(gt=0)


@router.post("/{result_id}/abandon")
def abandon_exam(result_id: int, request: AbandonExamRequest):
    if result_id <= 0:
        raise HTTPException(status_code=400, detail="Invalid result ID.")

    connection = get_connection()

    try:
        cursor = connection.cursor()
        cursor.execute(
            """
            SELECT UserId, Status
            FROM dbo.ExamResults WITH (UPDLOCK, ROWLOCK)
            WHERE ResultId = ?
            """,
            result_id
        )
        result = cursor.fetchone()
        if result is None:
            raise HTTPException(status_code=404, detail="Exam result not found.")
        if result.UserId != request.user_id:
            raise HTTPException(
                status_code=403,
                detail="This exam result belongs to another student."
            )
        if result.Status == "Abandoned":
            return {"result_id": result_id, "status": "Abandoned"}
        if result.Status != "InProgress":
            raise HTTPException(
                status_code=409,
                detail="A completed exam cannot be abandoned."
            )

        cursor.execute(
            """
            UPDATE dbo.ExamResults
            SET Status = 'Abandoned',
                CompletedAt = SYSDATETIME(),
                DurationSeconds = DATEDIFF(SECOND, StartedAt, SYSDATETIME())
            WHERE ResultId = ? AND Status = 'InProgress'
            """,
            result_id
        )
        connection.commit()
        return {"result_id": result_id, "status": "Abandoned"}

    except HTTPException:
        connection.rollback()
        raise
    except pyodbc.Error as exc:
        connection.rollback()
        print("Abandon exam database error:", exc)
        raise HTTPException(
            status_code=500,
            detail="Failed to close the exam attempt."
        ) from exc
    finally:
        connection.close()


@router.get("")
def get_exam_results():
    connection = get_connection()

    try:
        cursor = connection.cursor()
        cursor.execute(
            """
            SELECT
                result.ResultId,
                result.UserId,
                users.FullName,
                users.Email,
                result.ExamId,
                exams.ExamName,
                topics.TopicName,
                result.Score,
                result.TotalQuestions,
                exams.PassMark,
                result.StartedAt,
                result.CompletedAt,
                result.DurationSeconds,
                result.Status,
                result.IsReleased
            FROM dbo.ExamResults AS result
            INNER JOIN dbo.Users AS users
                ON users.UserId = result.UserId
            LEFT JOIN dbo.Exams AS exams
                ON exams.ExamId = result.ExamId
            LEFT JOIN dbo.Topics AS topics
                ON topics.TopicId = exams.TopicId
            ORDER BY COALESCE(result.CompletedAt, result.StartedAt) DESC,
                result.ResultId DESC
            """
        )

        results = []
        for row in cursor.fetchall():
            total_questions = row.TotalQuestions
            percentage = (
                row.Score * 100 / total_questions
                if total_questions
                else 0
            )

            results.append({
                "result_id": row.ResultId,
                "user_id": row.UserId,
                "student_name": row.FullName,
                "student_email": row.Email,
                "exam_id": row.ExamId,
                "exam_name": row.ExamName,
                "topic_name": row.TopicName,
                "score": row.Score,
                "total_questions": total_questions,
                "percentage": percentage,
                "pass_mark": (
                    float(row.PassMark) if row.PassMark is not None else None
                ),
                "started_at": row.StartedAt.isoformat() if row.StartedAt else None,
                "completed_at": (
                    row.CompletedAt.isoformat()
                    if row.CompletedAt else None
                ),
                "duration_seconds": row.DurationSeconds,
                "status": row.Status,
                "is_released": bool(row.IsReleased)
            })

        return {"results": results}

    except pyodbc.Error as exc:
        print("Get exam results database error:", exc)
        raise HTTPException(
            status_code=500,
            detail="Failed to retrieve exam results."
        ) from exc
    finally:
        connection.close()