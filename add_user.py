from app.db.session import SessionLocal
from app.models.user import User
from app.core.security import get_password_hash
import os
from dotenv import load_dotenv

load_dotenv()

db = SessionLocal()
email = "test@absolutebuilders.com"
password = "absolutebuilders"

try:
    user = db.query(User).filter(User.email == email).first()
    if user:
        print("User already exists!")
    else:
        hashed_password = get_password_hash(password)
        new_user = User(email=email, hashed_password=hashed_password, full_name="Absolute Builders Test")
        db.add(new_user)
        db.commit()
        print(f"User {email} created successfully!")
except Exception as e:
    db.rollback()
    print(f"Error: {e}")
finally:
    db.close()
