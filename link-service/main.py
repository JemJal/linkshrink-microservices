# link-service/main.py

import os
import uuid
from typing import Optional

import nanoid
from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt
from pydantic import BaseModel
from sqlalchemy import create_engine, Column, String
# --- THIS IS THE FIXED LINE ---
from sqlalchemy.orm import sessionmaker, Session
from sqlalchemy.ext.declarative import declarative_base # This was missing
# -----------------------------

# ===============================================
# ===         NEW CONFIGURATION SECTION         ===
# ===============================================
SECRET_KEY = os.getenv("JWT_SECRET_KEY")
ALGORITHM = "HS256"

if SECRET_KEY is None:
    raise RuntimeError("JWT_SECRET_KEY environment variable is not set!")

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")

# ===============================================

# --- Configuration ---
DATABASE_URL = os.getenv("DATABASE_URL")

# --- Database Setup ---
Base = declarative_base() # Now this line will work
if DATABASE_URL is None:
    raise RuntimeError("DATABASE_URL environment variable is not set!")
engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

class Link(Base):
    __tablename__ = "links"
    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    short_code = Column(String, unique=True, index=True, nullable=False)
    original_url = Column(String, nullable=False)
    user_id = Column(String, index=True, nullable=False)

Base.metadata.create_all(bind=engine)

# Pydantic Schemas
class User(BaseModel):
    id: str
    email: str

class LinkCreate(BaseModel):
    original_url: str

class LinkResponse(BaseModel):
    short_url: str
    original_url: str

# FastAPI Application
app = FastAPI(title="Link Service")

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

async def get_current_user(token: str = Depends(oauth2_scheme)):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        email: str = payload.get("sub")
        user_id: str = payload.get("user_id")
        if email is None or user_id is None:
            raise credentials_exception
        return User(id=user_id, email=email)
    except JWTError:
        raise credentials_exception

@app.get("/health", status_code=status.HTTP_200_OK)
def health_check():
    return {"status": "ok"}
    
@app.post("/links", response_model=LinkResponse, status_code=status.HTTP_201_CREATED)
def create_link(
    link: LinkCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    short_code = nanoid.generate(size=7)
    
    new_link = Link(
        original_url=link.original_url, 
        short_code=short_code,
        user_id=current_user.id
    )

    db.add(new_link)
    db.commit()
    db.refresh(new_link)
    
    return {"short_url": f"http://localhost:8080/{new_link.short_code}", "original_url": new_link.original_url}

@app.get("/links", response_model=list[LinkResponse])
def get_user_links(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    user_links = db.query(Link).filter(Link.user_id == current_user.id).all()
    
    return [
        {
            "short_url": f"http://localhost:8080/{link.short_code}",
            "original_url": link.original_url
        }
        for link in user_links
    ]