# user-service/main.py
import os
from sqlalchemy import create_engine, Column, String, TIMESTAMP, text
from sqlalchemy.orm import sessionmaker
from sqlalchemy.ext.declarative import declarative_base
from pydantic import BaseModel
from fastapi import FastAPI, Depends, HTTPException
from passlib.context import CryptContext
import uuid

# --- Configuration ---
# Read the database URL from an environment variable
DATABASE_URL = os.getenv("DATABASE_URL")

# --- Database Setup ---
Base = declarative_base()
engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# SQLAlchemy Model (Table definition)
class User(Base):
    __tablename__ = "users"
    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    email = Column(String, unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=False)

# Create the table if it doesn't exist
Base.metadata.create_all(bind=engine)

# --- Pydantic Schemas (for request/response validation) ---
class UserCreate(BaseModel):
    email: str
    password: str

class UserResponse(BaseModel):
    id: str
    email: str

# --- Password Hashing ---
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# --- FastAPI Application ---
app = FastAPI(title="User Service")

# Dependency to get a DB session
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

@app.post("/users", response_model=UserResponse, status_code=201)
def create_user(user: UserCreate, db = Depends(get_db)):
    # Check if user already exists
    db_user = db.query(User).filter(User.email == user.email).first()
    if db_user:
        raise HTTPException(status_code=400, detail="Email already registered")
    
    hashed_password = pwd_context.hash(user.password)
    new_user = User(email=user.email, hashed_password=hashed_password)
    
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    
    return new_user

@app.get("/ping")
def ping():
    return {"response": "User service is alive!"}

# TODO: Implement POST /token endpoint