from getpass import getpass

from dotenv import load_dotenv

from app.db.session import SessionLocal
from app.models.user import User
from app.core.security import get_password_hash


load_dotenv()


def main():
    print("\n=== Create Absolute Builders User ===\n")

    email = input("Email: ").strip().lower()
    full_name = input("Full name: ").strip()

    if not email:
        print("Error: Email is required.")
        return

    if not full_name:
        print("Error: Full name is required.")
        return

    password = getpass("Password: ")
    confirm_password = getpass("Confirm password: ")

    if not password:
        print("Error: Password is required.")
        return

    if password != confirm_password:
        print("Error: Passwords do not match.")
        return

    db = SessionLocal()

    try:
        existing_user = db.query(User).filter(User.email == email).first()

        if existing_user:
            print(f"Error: User {email} already exists.")
            return

        new_user = User(
            email=email,
            full_name=full_name,
            hashed_password=get_password_hash(password),
            is_active=True,
        )

        db.add(new_user)
        db.commit()
        db.refresh(new_user)

        print(f"\nUser {new_user.email} created successfully!")
        print(f"User ID: {new_user.id}")

    except Exception as e:
        db.rollback()
        print(f"Error creating user: {e}")

    finally:
        db.close()


if __name__ == "__main__":
    main()