
import pyodbc
from fastapi import APIRouter, HTTPException, Path
from pydantic import BaseModel, EmailStr, Field, field_validator
from passlib.context import CryptContext

from database.connection import get_connection

router = APIRouter(prefix="/users", tags=["Users"])
pwd_context = CryptContext(
    schemes=["bcrypt"],
    deprecated="auto" 
)
# Request model for registration
class RegisterUser(BaseModel):
    full_name: str = Field(min_length=2, max_length=150)
    region: str = Field(min_length=1, max_length=100)
    address: str = Field(min_length=1, max_length=250)
    role: str = Field(default="User", max_length=50)
    phone: str = Field(min_length=7, max_length=20)
    email: EmailStr
    password: str = Field(min_length=8, max_length=72)

    @field_validator("email")
    @classmethod
    def normalize_email(cls, value):
        return str(value).strip().lower()

    @field_validator("phone")
    @classmethod
    def normalize_phone(cls, value):
        return value.strip()

    @field_validator("role")
    @classmethod
    def force_user_role(cls, value):
        return "User"

    @field_validator("password")
    @classmethod
    def validate_password(cls, value):
        if len(value.encode("utf-8")) > 72:
            raise ValueError("Password must be 72 bytes or fewer.")
        return value


# Request model for login
class LoginUser(BaseModel):
    email: EmailStr
    password: str

    @field_validator("email")
    @classmethod
    def normalize_email(cls, value):
        return str(value).strip().lower()


class UpdateUser(BaseModel):
    full_name: str = Field(min_length=2, max_length=150)
    region: str = Field(min_length=1, max_length=100)
    address: str = Field(min_length=1, max_length=250)
    role: str = Field(max_length=50)
    phone: str = Field(min_length=7, max_length=20)
    email: EmailStr


# Register user
@router.post("/register", status_code=201)
def register(user: RegisterUser):
    connection = get_connection()

    try:
        cursor = connection.cursor()
        cursor.execute("SET TRANSACTION ISOLATION LEVEL SERIALIZABLE")

        cursor.execute(
            """
            SELECT UserId
            FROM dbo.Users
            WHERE LOWER(LTRIM(RTRIM(Email))) = ?
                OR LTRIM(RTRIM(Phone)) = ?
            """,
            user.email,
            user.phone
        )

        if cursor.fetchone():
            raise HTTPException(
                status_code=409,
                detail="This email or phone number is already registered."
            )

        password_hash = pwd_context.hash(user.password)

        cursor.execute(
            """
            SET NOCOUNT ON;
            INSERT INTO dbo.Users
                (FullName, Region, Address, Role, Phone, Email, PasswordHash)
            VALUES (?, ?, ?, ?, ?, ?, ?);

            SELECT UserId, CreatedAt
            FROM dbo.Users
            WHERE UserId = SCOPE_IDENTITY();
            """,
            user.full_name,
            user.region,
            user.address,
            "User",
            user.phone,
            user.email,
            password_hash
        )

        result = cursor.fetchone()

        if result is None:
            raise HTTPException(
                status_code=500,
                detail="Registration did not return the new user record."
            )

        user_id, created_at = result
        connection.commit()

        return {
            "message": "Registration successful",
            "user_id": user_id,
            "full_name": user.full_name,
            "region": user.region,
            "address": user.address,
            "role": "User",
            "phone": user.phone,
            "email": user.email,
            "created_at": created_at.isoformat() if created_at else None
        }

    except HTTPException:
        connection.rollback()
        raise

    except pyodbc.Error as exc:
        connection.rollback()
        print("Registration database error:", exc)
        if "2601" in str(exc) or "2627" in str(exc):
            raise HTTPException(
                status_code=409,
                detail="This email or phone number is already registered."
            ) from exc
        raise HTTPException(
            status_code=500,
            detail=f"Database error while saving the user: {exc}"
        )

    finally:
        connection.close()


# Login user
@router.post("/login")
def login(user: LoginUser):
    connection = get_connection()

    try:
        cursor = connection.cursor()

        cursor.execute(
            """
            SELECT UserId, FullName, Email, PasswordHash, Role
            FROM dbo.Users
            WHERE LOWER(LTRIM(RTRIM(Email))) = ?
            """,
            str(user.email).strip().lower()
        )

        result = cursor.fetchone()

        if result is None:
            raise HTTPException(
                status_code=404,
                detail="This email is not registered. Please sign up first."
            )

        if not pwd_context.verify(user.password, result.PasswordHash):
            raise HTTPException(
                status_code=401,
                detail="Incorrect password."
            )

        return {
            "message": "Login successful",
            "user_id": result.UserId,
            "full_name": result.FullName,
            "email": result.Email,
            "role": result.Role
        }

    except HTTPException:
        raise

    except pyodbc.Error as exc:
        print("Login database error:", exc)
        raise HTTPException(
            status_code=500,
            detail="Login failed because of a database error."
        )

    finally:
        connection.close()

@router.get("")
def get_users():
    connection = get_connection()

    try:
        cursor = connection.cursor()

        cursor.execute("""
            SELECT UserId, FullName, Region, Address, Role, Phone, Email
            FROM dbo.Users
            ORDER BY UserId DESC
        """)

        rows = cursor.fetchall()

        return {
            "users": [
                {
                    "user_id": row.UserId,
                    "full_name": row.FullName,
                    "region": row.Region,
                    "address": row.Address,
                    "role": row.Role,
                    "phone": row.Phone,
                    "email": row.Email,
                }
                for row in rows
            ]
        }

    except Exception as exc:
        print("Get users database error:", exc)
        raise HTTPException(
            status_code=500,
            detail="Failed to retrieve users."
        )

    finally:
        connection.close()


@router.put("/{user_id}")
def update_user(user: UpdateUser, user_id: int = Path(gt=0)):
    connection = get_connection()

    try:
        cursor = connection.cursor()
        cursor.execute(
            """
            SELECT UserId
            FROM dbo.Users
            WHERE UserId = ?
            """,
            user_id
        )
        if cursor.fetchone() is None:
            raise HTTPException(status_code=404, detail="User not found.")

        cursor.execute(
            """
            SELECT UserId
            FROM dbo.Users
            WHERE (LOWER(LTRIM(RTRIM(Email))) = ?
                OR LTRIM(RTRIM(Phone)) = ?) AND UserId <> ?
            """,
            str(user.email).strip().lower(),
            user.phone.strip(),
            user_id
        )
        if cursor.fetchone() is not None:
            raise HTTPException(
                status_code=409,
                detail="This email or phone number is already in use."
            )

        cursor.execute(
            """
            UPDATE dbo.Users
            SET FullName = ?, Region = ?, Address = ?, Role = ?,
                Phone = ?, Email = ?
            WHERE UserId = ?
            """,
            user.full_name.strip(),
            user.region.strip(),
            user.address.strip(),
            user.role.strip(),
            user.phone.strip(),
            str(user.email).strip().lower(),
            user_id
        )
        connection.commit()
        return {"message": "User updated successfully"}

    except HTTPException:
        connection.rollback()
        raise
    except pyodbc.Error as exc:
        connection.rollback()
        print("Update user database error:", exc)
        raise HTTPException(
            status_code=500,
            detail="Failed to update the user."
        )
    finally:
        connection.close()


@router.delete("/{user_id}")
def delete_user(user_id: int = Path(gt=0)):
    connection = get_connection()

    try:
        cursor = connection.cursor()
        cursor.execute(
            "DELETE FROM dbo.Users WHERE UserId = ?",
            user_id
        )
        if cursor.rowcount == 0:
            raise HTTPException(status_code=404, detail="User not found.")

        connection.commit()
        return {"message": "User deleted successfully"}

    except HTTPException:
        connection.rollback()
        raise
    except pyodbc.Error as exc:
        connection.rollback()
        print("Delete user database error:", exc)
        if "547" in str(exc):
            raise HTTPException(
                status_code=409,
                detail=(
                    "This user cannot be deleted because related records "
                    "exist."
                )
            )
        raise HTTPException(
            status_code=500,
            detail="Failed to delete the user."
        )
    finally:
        connection.close()
