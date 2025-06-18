# link-service/main.py - v2.1 with Custom Short Links

import os
import uuid
from typing import Optional

import nanoid
from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt
from pydantic import BaseModel
from sqlalchemy import create_engine, Column, String, or_
from sqlalchemy.orm import sessionmaker, Session
from sqlalchemy.ext.declarative import declarative_base

# ===============================================
# ===             CONFIGURATION SECTION             ===
# ===============================================
SECRET_KEY = os.getenv("JWT_SECRET_KEY")
ALGORITHM = "HS256"
DATABASE_URL = os.getenv("DATABASE_URL")
BASE_URL = os.getenv("BASE_URL", "http://localhost:8080")

if not all([SECRET_KEY, DATABASE_URL]):
    raise RuntimeError("Required environment variables (JWT_SECRET_KEY, DATABASE_URL) are not set!")

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")

# ===============================================
# ===             DATABASE SETUP              ===
# ===============================================
Base = declarative_base()
engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# UPDATED: Database model with new custom_short_code column
class Link(Base):
    __tablename__ = "links"
    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    nanoid_code = Column(String, unique=True, index=True, nullable=False)
    custom_short_code = Column(String, unique=True, index=True, nullable=True)
    original_url = Column(String, nullable=False)
    user_id = Column(String, index=True, nullable=False)

Base.metadata.create_all(bind=engine)

# ===============================================
# ===            PYDANTIC SCHEMAS               ===
# ===============================================
class User(BaseModel):
    id: str
    email: str

# UPDATED: LinkCreate now accepts an optional custom short code
class LinkCreate(BaseModel):
    original_url: str
    custom_short_code: Optional[str] = None

class LinkResponse(BaseModel):
    short_url: str
    original_url: str

class InternalLinkResponse(BaseModel):
    original_url: str

# ===============================================
# ===         FASTAPI APP & DEPENDENCIES        ===
# ===============================================
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

# ===============================================
# ===              API ENDPOINTS                ===
# ===============================================
@app.get("/health", status_code=status.HTTP_200_OK)
def health_check():
    return {"status": "ok"}

@app.get("/internal/links/{short_code}", response_model=InternalLinkResponse)
def get_link_by_short_code(short_code: str, db: Session = Depends(get_db)):
    # UPDATED: Search in both columns for a match
    link = db.query(Link).filter(
        or_(Link.nanoid_code == short_code, Link.custom_short_code == short_code)
    ).first()
    if not link:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Link not found")
    return {"original_url": link.original_url}

@app.post("/links", response_model=LinkResponse, status_code=status.HTTP_201_CREATED)
def create_link(
    link: LinkCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    # --- UPDATED: New logic for custom short links ---
    short_code_to_use = None
    
    if link.custom_short_code:
        # Step 1: Validate the custom code
        if len(link.custom_short_code) < 5:
            raise HTTPException(status_code=400, detail="Custom name must be at least 5 characters.")
        if not link.custom_short_code.isalnum():
             raise HTTPException(status_code=400, detail="Custom name can only contain letters and numbers.")

        # Step 2: Check for uniqueness
        existing_link = db.query(Link).filter(Link.custom_short_code == link.custom_short_code).first()
        if existing_link:
            raise HTTPException(status_code=409, detail="This custom name is already taken.")
        
        short_code_to_use = link.custom_short_code

    # Always generate a random nanoid for internal reference
    nanoid_code = nanoid.generate(size=7)
    
    new_link = Link(
        original_url=link.original_url, 
        nanoid_code=nanoid_code, # <-- Use new column name
        custom_short_code=link.custom_short_code, # <-- Save the custom code
        user_id=current_user.id
    )

    db.add(new_link)
    db.commit()
    db.refresh(new_link)
    
    # Step 3: Return the correct URL
    final_code = short_code_to_use if short_code_to_use else nanoid_code
    return {"short_url": f"{BASE_URL}/r/{final_code}", "original_url": new_link.original_url}

@app.get("/links", response_model=list[LinkResponse])
def get_user_links(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    user_links = db.query(Link).filter(Link.user_id == current_user.id).all()
    
    return [
        {
            # Use the custom code if it exists, otherwise use the nanoid code
            "short_url": f"{BASE_URL}/r/{link.custom_short_code or link.nanoid_code}",
            "original_url": link.original_url
        }
        for link in user_links
    ]