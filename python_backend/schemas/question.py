
from pydantic import BaseModel, Field
from typing import List


class QuestionOptionCreate(BaseModel):
    label: str = Field(min_length=1, max_length=1)
    text: str = Field(min_length=1)
    is_correct: bool = False


class QuestionCreate(BaseModel):
    topic_id: int
    question_text: str = Field(min_length=1)
    options: List[QuestionOptionCreate] = Field(min_length=4, max_length=4)
