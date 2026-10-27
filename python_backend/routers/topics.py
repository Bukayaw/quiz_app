
import pyodbc
from fastapi import APIRouter, HTTPException, Path, Query
from pydantic import BaseModel, Field

from database.connection import get_connection

router = APIRouter(prefix="/topics", tags=["Topics"])


class CreateTopic(BaseModel):
    topic_name: str = Field(min_length=1, max_length=100)


class TopicStatusUpdate(BaseModel):
    is_active: bool


@router.get("")
def get_topics(include_inactive: bool = Query(default=False)):
    connection = get_connection()

    try:
        cursor = connection.cursor()
        cursor.execute(
            """
            SELECT TopicId, TopicName, IsActive
            FROM dbo.Topics
            WHERE (? = 1 OR IsActive = 1)
            ORDER BY TopicName
            """,
            include_inactive
        )

        rows = cursor.fetchall()

        return {
            "topics": [
                {
                    "topic_id": row.TopicId,
                    "topic_name": row.TopicName,
                    "is_active": bool(row.IsActive)
                }
                for row in rows
            ]
        }

    except pyodbc.Error as exc:
        print("Get topics database error:", exc)
        raise HTTPException(
            status_code=500,
            detail="Failed to retrieve topics."
        )
    finally:
        connection.close()


@router.patch("/{topic_id}/status")
def update_topic_status(
    status: TopicStatusUpdate,
    topic_id: int = Path(gt=0)
):
    connection = get_connection()
    try:
        cursor = connection.cursor()
        cursor.execute(
            """
            UPDATE dbo.Topics
            SET IsActive = ?
            WHERE TopicId = ?
            """,
            status.is_active,
            topic_id
        )
        if cursor.rowcount == 0:
            raise HTTPException(status_code=404, detail="Topic not found.")

        connection.commit()
        return {
            "message": (
                "Topic enabled successfully"
                if status.is_active
                else "Topic disabled successfully"
            ),
            "topic_id": topic_id,
            "is_active": status.is_active
        }

    except HTTPException:
        connection.rollback()
        raise
    except pyodbc.Error as exc:
        connection.rollback()
        print("Update topic status database error:", exc)
        raise HTTPException(
            status_code=500,
            detail="Failed to update topic status."
        )
    finally:
        connection.close()


@router.post("", status_code=201)
def create_topic(topic: CreateTopic):
    topic_name = topic.topic_name.strip()
    if not topic_name:
        raise HTTPException(
            status_code=400,
            detail="Topic name cannot be empty."
        )

    connection = get_connection()

    try:
        cursor = connection.cursor()
        cursor.execute(
            """
            SELECT TopicId
            FROM dbo.Topics
            WHERE TopicName = ? AND IsActive = 1
            """,
            topic_name
        )
        if cursor.fetchone() is not None:
            raise HTTPException(
                status_code=409,
                detail="An active topic with this name already exists."
            )

        cursor.execute(
            """
            INSERT INTO dbo.Topics (TopicName, IsActive)
            OUTPUT INSERTED.TopicId
            VALUES (?, 1)
            """,
            topic_name
        )
        result = cursor.fetchone()
        if result is None:
            raise HTTPException(
                status_code=500,
                detail="Topic creation did not return the new topic ID."
            )

        connection.commit()
        return {
            "message": "Topic created successfully",
            "topic_id": result.TopicId,
            "topic_name": topic_name
        }

    except HTTPException:
        connection.rollback()
        raise
    except pyodbc.Error as exc:
        connection.rollback()
        print("Create topic database error:", exc)
        raise HTTPException(
            status_code=500,
            detail="Failed to create topic."
        )
    finally:
        connection.close()


@router.put("/{topic_id}")
def update_topic(topic: CreateTopic, topic_id: int = Path(gt=0)):
    topic_name = topic.topic_name.strip()
    if not topic_name:
        raise HTTPException(
            status_code=400,
            detail="Topic name cannot be empty."
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
            topic_id
        )
        if cursor.fetchone() is None:
            raise HTTPException(status_code=404, detail="Topic not found.")

        cursor.execute(
            """
            SELECT TopicId
            FROM dbo.Topics
            WHERE TopicName = ? AND IsActive = 1 AND TopicId <> ?
            """,
            topic_name,
            topic_id
        )
        if cursor.fetchone() is not None:
            raise HTTPException(
                status_code=409,
                detail="An active topic with this name already exists."
            )

        cursor.execute(
            """
            UPDATE dbo.Topics
            SET TopicName = ?
            WHERE TopicId = ? AND IsActive = 1
            """,
            topic_name,
            topic_id
        )
        connection.commit()
        return {
            "message": "Topic updated successfully",
            "topic_id": topic_id,
            "topic_name": topic_name
        }

    except HTTPException:
        connection.rollback()
        raise
    except pyodbc.Error as exc:
        connection.rollback()
        print("Update topic database error:", exc)
        raise HTTPException(
            status_code=500,
            detail="Failed to update topic."
        )
    finally:
        connection.close()


@router.delete("/{topic_id}")
def delete_topic(topic_id: int = Path(gt=0)):
    connection = get_connection()
    try:
        cursor = connection.cursor()
        cursor.execute(
            """
            UPDATE dbo.Topics
            SET IsActive = 0
            WHERE TopicId = ? AND IsActive = 1
            """,
            topic_id
        )
        if cursor.rowcount == 0:
            raise HTTPException(status_code=404, detail="Topic not found.")

        connection.commit()
        return {"message": "Topic deleted successfully"}

    except HTTPException:
        connection.rollback()
        raise
    except pyodbc.Error as exc:
        connection.rollback()
        print("Delete topic database error:", exc)
        raise HTTPException(
            status_code=500,
            detail="Failed to delete topic."
        )
    finally:
        connection.close()
