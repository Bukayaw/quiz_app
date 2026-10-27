
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from routers import dashboard, users, questions, topics, results

app = FastAPI(title="Quiz App API")
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$",
    allow_methods=["*"],
    allow_headers=["*"],
)

# Register endpoint groups
app.include_router(users.router)
app.include_router(questions.router)
app.include_router(topics.router)
app.include_router(dashboard.router)
app.include_router(results.router)


@app.get("/")
def home():
    return {
        "message": "Quiz App API is running",
        "docs": "/docs"
    }
