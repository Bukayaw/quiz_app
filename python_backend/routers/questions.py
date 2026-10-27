import pyodbc
from fastapi import APIRouter, HTTPException, Path, Query

from database.connection import get_connection
from schemas.question import QuestionCreate

router = APIRouter(prefix="/questions", tags=["Questions"])


# GET: Retrieve questions and their options
@router.get("")
def get_questions(
    topic_id: int | None = Query(default=None, gt=0),
    topic: str | None = Query(default=None)
):
    connection = get_connection()

    try:
        cursor = connection.cursor()

        sql = """
            SELECT
                q.QuestionId,
                q.TopicId,
                q.QuestionText,
                q.CreatedAt,
                t.TopicName
            FROM dbo.Questions AS q
            INNER JOIN dbo.Topics AS t
                ON q.TopicId = t.TopicId
            WHERE q.IsActive = 1
            AND t.IsActive = 1
        """

        params = []

        if topic_id is not None:
            sql += " AND q.TopicId = ?"
            params.append(topic_id)

        if topic:
            sql += " AND t.TopicName = ?"
            params.append(topic.strip())

        sql += " ORDER BY q.QuestionId"

        cursor.execute(sql, params)
        rows = cursor.fetchall()

        questions = []

        for row in rows:
            question_id = row.QuestionId

            cursor.execute(
                """
                SELECT
                    OptionId,
                    OptionLabel,
                    OptionText,
                    IsCorrect
                FROM dbo.QuestionOptions
                WHERE QuestionId = ?
                ORDER BY OptionLabel
                """,
                question_id
            )

            options = cursor.fetchall()

            questions.append({
                "question_id": question_id,
                "topic_id": row.TopicId,
                "topic_name": row.TopicName,
                "question_text": row.QuestionText,
                "created_at": (
                    row.CreatedAt.isoformat()
                    if row.CreatedAt else None
                ),
                "options": [
                    {
                        "option_id": option.OptionId,
                        "label": option.OptionLabel.strip(),
                        "text": option.OptionText,
                        "is_correct": bool(option.IsCorrect)
                    }
                    for option in options
                ]
            })

        return {"questions": questions}

    except pyodbc.Error as exc:
        print("Get questions database error:", exc)
        raise HTTPException(
            status_code=500,
            detail="Failed to retrieve questions."
        )

    finally:
        connection.close()


# POST: Create a question with four options
@router.post("", status_code=201)
def create_question(question: QuestionCreate):

    # Validate exactly four options
    if len(question.options) != 4:
        raise HTTPException(
            status_code=400,
            detail="Exactly four options are required."
        )

    labels = [option.label for option in question.options]

    if len(set(labels)) != 4 or set(labels) != {"A", "B", "C", "D"}:
        raise HTTPException(
            status_code=400,
            detail="Options must have unique labels A, B, C, and D."
        )

    if any(not option.text.strip() for option in question.options):
        raise HTTPException(
            status_code=400,
            detail="Option text cannot be empty."
        )

    if not question.question_text.strip():
        raise HTTPException(
            status_code=400,
            detail="Question text cannot be empty."
        )

    if sum(option.is_correct for option in question.options) != 1:
        raise HTTPException(
            status_code=400,
            detail="Exactly one option must be correct."
        )

    connection = get_connection()

    try:
        cursor = connection.cursor()

        # Verify that the topic exists and is active
        cursor.execute(
            """
            SELECT TopicId
            FROM dbo.Topics
            WHERE TopicId = ? AND IsActive = 1
            """,
            question.topic_id
        )

        if cursor.fetchone() is None:
            raise HTTPException(
                status_code=404,
                detail="Topic not found or inactive."
            )

        # Insert question
        cursor.execute(
            """
            INSERT INTO dbo.Questions (TopicId, QuestionText)
            OUTPUT INSERTED.QuestionId
            VALUES (?, ?)
            """,
            question.topic_id,
            question.question_text.strip()
        )

        question_id = cursor.fetchone()[0]

        # Insert options
        for option in question.options:
            cursor.execute(
                """
                INSERT INTO dbo.QuestionOptions
                    (QuestionId, OptionLabel, OptionText, IsCorrect)
                VALUES (?, ?, ?, ?)
                """,
                question_id,
                option.label,
                option.text.strip(),
                option.is_correct
            )

        connection.commit()

        return {
            "message": "Question created successfully",
            "question_id": question_id,
            "topic_id": question.topic_id
        }

    except HTTPException:
        connection.rollback()
        raise

    except pyodbc.Error as exc:
        connection.rollback()
        print("Create question database error:", exc)
        raise HTTPException(
            status_code=500,
            detail="Failed to save the question and options."
        )

    finally:
        connection.close()


@router.put("/{question_id}")
def update_question(
    question_id: int = Path(gt=0),
    question: QuestionCreate = ...
):
    if len(question.options) != 4:
        raise HTTPException(
            status_code=400,
            detail="Exactly four options are required."
        )

    labels = [option.label for option in question.options]
    if len(set(labels)) != 4 or set(labels) != {"A", "B", "C", "D"}:
        raise HTTPException(
            status_code=400,
            detail="Options must have unique labels A, B, C, and D."
        )
    if any(not option.text.strip() for option in question.options):
        raise HTTPException(
            status_code=400,
            detail="Option text cannot be empty."
        )
    if not question.question_text.strip():
        raise HTTPException(
            status_code=400,
            detail="Question text cannot be empty."
        )
    if sum(option.is_correct for option in question.options) != 1:
        raise HTTPException(
            status_code=400,
            detail="Exactly one option must be correct."
        )

    connection = get_connection()
    try:
        cursor = connection.cursor()
        cursor.execute(
            """
            SELECT QuestionId
            FROM dbo.Questions
            WHERE QuestionId = ? AND IsActive = 1
            """,
            question_id
        )
        if cursor.fetchone() is None:
            raise HTTPException(status_code=404, detail="Question not found.")

        cursor.execute(
            """
            SELECT TopicId
            FROM dbo.Topics
            WHERE TopicId = ? AND IsActive = 1
            """,
            question.topic_id
        )
        if cursor.fetchone() is None:
            raise HTTPException(
                status_code=404,
                detail="Topic not found or inactive."
            )

        cursor.execute(
            """
            UPDATE dbo.Questions
            SET TopicId = ?, QuestionText = ?
            WHERE QuestionId = ?
            """,
            question.topic_id,
            question.question_text.strip(),
            question_id
        )

        for option in question.options:
            cursor.execute(
                """
                UPDATE dbo.QuestionOptions
                SET OptionText = ?, IsCorrect = ?
                WHERE QuestionId = ? AND OptionLabel = ?
                """,
                option.text.strip(),
                option.is_correct,
                question_id,
                option.label
            )
            if cursor.rowcount == 0:
                cursor.execute(
                    """
                    INSERT INTO dbo.QuestionOptions
                        (QuestionId, OptionLabel, OptionText, IsCorrect)
                    VALUES (?, ?, ?, ?)
                    """,
                    question_id,
                    option.label,
                    option.text.strip(),
                    option.is_correct
                )

        connection.commit()
        return {"message": "Question updated successfully"}

    except HTTPException:
        connection.rollback()
        raise
    except pyodbc.Error as exc:
        connection.rollback()
        print("Update question database error:", exc)
        raise HTTPException(
            status_code=500,
            detail="Failed to update the question and options."
        )
    finally:
        connection.close()


@router.delete("/{question_id}")
def delete_question(question_id: int = Path(gt=0)):
    connection = get_connection()
    try:
        cursor = connection.cursor()
        cursor.execute(
            """
            UPDATE dbo.Questions
            SET IsActive = 0
            WHERE QuestionId = ? AND IsActive = 1
            """,
            question_id
        )
        if cursor.rowcount == 0:
            raise HTTPException(status_code=404, detail="Question not found.")

        connection.commit()
        return {"message": "Question deleted successfully"}
    except HTTPException:
        connection.rollback()
        raise
    except pyodbc.Error as exc:
        connection.rollback()
        print("Delete question database error:", exc)
        raise HTTPException(
            status_code=500,
            detail="Failed to delete the question."
        )
    finally:
        connection.close()


@router.post("", status_code=201)
def create_question(question: QuestionCreate):
    # Validate exactly four options with unique A-D labels.
    if len(question.options) != 4:
        raise HTTPException(
            status_code=400,
            detail="Exactly four options are required."
        )

    labels = [option.label for option in question.options]

    if len(set(labels)) != 4 or set(labels) != {"A", "B", "C", "D"}:
        raise HTTPException(
            status_code=400,
            detail="Options must have unique labels A, B, C, and D."
        )

    if any(not option.text.strip() for option in question.options):
        raise HTTPException(
            status_code=400,
            detail="Option text cannot be empty."
        )

    if not question.question_text.strip():
        raise HTTPException(
            status_code=400,
            detail="Question text cannot be empty."
        )

    if sum(option.is_correct for option in question.options) != 1:
        raise HTTPException(
            status_code=400,
            detail="Exactly one option must be correct."
        )

    connection = get_connection()

    try:
        cursor = connection.cursor()

        cursor.execute(
            """
            SELECT TopicId
            FROM dbo.Topics
            WHERE TopicId = ? AND IsActive = 1
            """,
            question.topic_id
        )

        if cursor.fetchone() is None:
            raise HTTPException(
                status_code=404,
                detail="Topic not found or inactive."
            )

        cursor.execute(
            """
            INSERT INTO dbo.Questions (TopicId, QuestionText)
            OUTPUT INSERTED.QuestionId
            VALUES (?, ?)
            """,
            question.topic_id,
            question.question_text.strip()
        )

        question_id = cursor.fetchone()[0]

        for option in question.options:
            cursor.execute(
                """
                INSERT INTO dbo.QuestionOptions
                    (QuestionId, OptionLabel, OptionText, IsCorrect)
                VALUES (?, ?, ?, ?)
                """,
                question_id,
                option.label,
                option.text.strip(),
                option.is_correct
            )

        connection.commit()

        return {
            "message": "Question created successfully",
            "question_id": question_id,
            "topic_id": question.topic_id
        }

    except HTTPException:
        connection.rollback()
        raise
    except pyodbc.Error as exc:
        connection.rollback()
        print("Create question database error:", exc)
        raise HTTPException(
            status_code=500,
            detail="Failed to save the question and options."
        )
    finally:
        connection.close()
