import pyodbc
from fastapi import APIRouter, HTTPException

from database.connection import get_connection

router = APIRouter(prefix="/dashboard", tags=["Dashboard"])


@router.get("/stats")
def get_dashboard_stats():
    connection = get_connection()

    try:
        cursor = connection.cursor()
        cursor.execute(
            """
            WITH LatestCompletedResults AS (
                SELECT
                    result.UserId,
                    result.Score,
                    result.TotalQuestions,
                    exams.PassMark,
                    ROW_NUMBER() OVER (
                        PARTITION BY result.UserId
                        ORDER BY result.CompletedAt DESC, result.ResultId DESC
                    ) AS AttemptRank
                FROM dbo.ExamResults AS result
                INNER JOIN dbo.Exams AS exams
                    ON exams.ExamId = result.ExamId
                WHERE result.Status = 'Completed'
            ),
            StudentsWithAttempts AS (
                SELECT DISTINCT UserId
                FROM dbo.ExamResults
            )
            SELECT
                (
                    SELECT COUNT_BIG(*)
                    FROM dbo.Users
                    WHERE UPPER(LTRIM(RTRIM(Role))) <> 'ADMIN'
                ) AS registered_users,
                (
                    SELECT COUNT_BIG(DISTINCT UserId)
                    FROM dbo.ExamResults
                ) AS exam_takers,
                (
                    SELECT COUNT_BIG(*)
                    FROM dbo.ExamResults
                ) AS exam_attempts,
                (
                    SELECT COUNT_BIG(*)
                    FROM dbo.Questions
                    WHERE IsActive = 1
                ) AS total_questions,
                (
                    SELECT COUNT_BIG(*)
                    FROM dbo.Topics
                    WHERE IsActive = 1 AND IsDeleted = 0
                ) AS total_topics,
                (
                    SELECT COUNT_BIG(*)
                    FROM dbo.Exams
                    WHERE IsActive = 1
                ) AS total_exams,
                (
                    SELECT COUNT_BIG(*)
                    FROM LatestCompletedResults
                    WHERE AttemptRank = 1
                        AND Score * 100.0 / NULLIF(TotalQuestions, 0)
                            >= PassMark
                ) AS passed_students,
                (
                    SELECT COUNT_BIG(*)
                    FROM LatestCompletedResults
                    WHERE AttemptRank = 1
                        AND Score * 100.0 / NULLIF(TotalQuestions, 0)
                            < PassMark
                ) AS failed_students,
                (
                    SELECT COUNT_BIG(*)
                    FROM dbo.Users AS users
                    LEFT JOIN StudentsWithAttempts AS attempts
                        ON attempts.UserId = users.UserId
                    WHERE UPPER(LTRIM(RTRIM(users.Role))) <> 'ADMIN'
                        AND attempts.UserId IS NULL
                ) AS students_not_taken_exam
            """
        )
        row = cursor.fetchone()

        if row is None:
            raise HTTPException(
                status_code=500,
                detail="Dashboard statistics were not returned."
            )

        return {
            "registered_users": row.registered_users,
            "exam_takers": row.exam_takers,
            "exam_attempts": row.exam_attempts,
            "total_questions": row.total_questions,
            "total_topics": row.total_topics,
            "total_exams": row.total_exams,
            "passed_students": row.passed_students,
            "failed_students": row.failed_students,
            "students_not_taken_exam": row.students_not_taken_exam
        }

    except HTTPException:
        raise
    except pyodbc.Error as exc:
        print("Get dashboard statistics database error:", exc)
        raise HTTPException(
            status_code=500,
            detail="Failed to retrieve dashboard statistics."
        ) from exc
    finally:
        connection.close()
