# Flask Portal Starter (with Meetings)
Features:
- Auth (login/register)
- Dashboard
- Goals tracking
- Document uploads
- Survey reports placeholder
- Chat placeholder
- **My Meetings** tab with two-button UX:
  - "Sign up for a meeting" (modal with date/time picker)
  - "Go to a meeting" (modal listing meetings with Join buttons)
  - Export any meeting as `.ics`

Quickstart:
python -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env
python run.py
