
import re
from pydantic import BaseModel, EmailStr, Field, field_validator


class RegisterUser(BaseModel):
    full_name: str = Field(min_length=6, max_length=100)
    region: str = Field(min_length=4, max_length=100)
    address: str = Field(min_length=4, max_length=200)
    role: str = "User"
    phone: str
    email: EmailStr
    password: str = Field(min_length=8, max_length=72)

    @field_validator("full_name")
    @classmethod
    def validate_full_name(cls, value):
        value = value.strip()
        if len(value) < 6:
            raise ValueError("Full name must contain at least 6 characters.")
        if not re.fullmatch(r"[A-Za-z ]+", value):
            raise ValueError(
                "Full name must contain English letters and spaces only."
            )
        return value

    @field_validator("region", "address")
    @classmethod
    def validate_text_fields(cls, value):
        value = value.strip()
        if len(value) < 4:
            raise ValueError("Must contain at least 4 characters.")
        return value

    @field_validator("role")
    @classmethod
    def validate_role(cls, value):
        # Public registration must not grant Admin privileges.
        return "User"

    @field_validator("phone")
    @classmethod
    def validate_phone(cls, value):
        value = value.strip()
        if not re.fullmatch(r"\+251[79]\d{8}", value):
            raise ValueError(
                "Phone must use +251 followed by 9 digits, starting with 9 or 7."
            )
        return value

    @field_validator("email")
    @classmethod
    def normalize_email(cls, value):
        return str(value).strip().lower()

    @field_validator("password")
    @classmethod
    def validate_password(cls, value):
        if len(value.encode("utf-8")) > 72:
            raise ValueError("Password must be 72 bytes or fewer.")
        return value
