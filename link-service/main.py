# link-service/main.py
import os
from sqlalchemy import create_engine, Column, String, TIMESTAMP, text
from sqlalchemy.orm import sessionmaker
from sqlalchemy.ext.declarative import declarative_base
from pydantic import BaseModel
from fastapi import FastAPI, Depends, HTTPException
import uuid
import nanoid

# --- Configuration ---
DATABASE_URL = os.getenv("DATABASE_URL")

# --- Database Setup ---
Base = declarative_base()
engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

class Link(Base):
    __tablename__ = "links"
    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    short_code = Column(String, unique=True, index=True, nullable=False)
    original_url = Column(String, nullable=False)
    user_id = Column(String, nullable=False) # TODO: Validate this user exists via API call

Base.metadata.create_all(bind=engine)

# --- Pydantic Schemas ---
class LinkCreate(BaseModel):
    original_url: str

class LinkResponse(BaseModel):
    short_url: str
    original_url: str

# --- FastAPI Application ---
app = FastAPI(title="Link Service")

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

@app.post("/links", response_model=LinkResponse, status_code=201)
def create_link(link: LinkCreate, db = Depends(get_db)):
    # TODO: In a real app, get user_id from JWT token
    fake_user_id = "user-123"
    short_code = nanoid.generate(size=7)
    
    new_link = Link(
        original_url=link.original_url, 
        short_code=short_code,
        user_id=fake_user_id
    )

    db.add(new_link)
    db.commit()
    db.refresh(new_link)
    
    # TODO: Use a proper domain from config
    return {"short_url": f"http://localhost:8080/{new_link.short_code}", "original_url": new_link.original_url}

@app.get("/ping")
def ping():
    return {"response": "Link service is alive!"}