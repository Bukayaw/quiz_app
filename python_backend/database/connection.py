
import pyodbc
from fastapi import HTTPException

CONNECTION_STRING = (
    "DRIVER={ODBC Driver 18 for SQL Server};"
    "SERVER=localhost;"
    "DATABASE=QuizApp;"
    "Trusted_Connection=yes;"
    "TrustServerCertificate=yes;"
)


def get_connection():
    try:
        return pyodbc.connect(CONNECTION_STRING, timeout=5)
    except pyodbc.Error as exc:
        print("SQL Server connection error:", exc)
        raise HTTPException(
            status_code=503,
            detail=f"Cannot connect to SQL Server: {exc}"
        )
