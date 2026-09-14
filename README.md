LinkedIn CV AnalyzerAn AI-powered application designed to extract LinkedIn profile data and provide intelligent CV analysis using the Groq LLM API. The project features a cross-platform Flutter frontend for the user interface and a Python Flask backend for web scraping and data processing.🏗 Architecture & Tech StackThis project uses a hybrid architecture split between a Dart/Flutter client and a Python web service:  Frontend (Flutter/Dart)Framework: Flutter (Supports Android, iOS, Web, macOS, Linux, and Windows).  State Management/UI: Core screens include home_screen.dart and results_screen.dart.  Services: Integrates custom services via linkedin_scraper.dart and groq_service.dart for AI inference.  Backend (Python)Framework: Flask 3.1.1 for serving the API and cv-analyzer.html.  Scraping: BeautifulSoup4 4.14.3 and Requests 2.33.1 for fetching and parsing profile data.  Deployment: Configured for WSGI environments with passenger_wsgi.py.  🚀 FeaturesCross-Platform UI: Beautiful, responsive interface built with Flutter that runs natively on mobile and desktop.Profile Scraping: Python-based scraper that extracts relevant professional experience and skills from LinkedIn URLs.AI CV Analysis: Deep integration with the Groq API to analyze the scraped data, providing feedback, summaries, or tailored resume advice.Web Interface: Includes an alternative or companion web-based CV analyzer endpoint.🛠 PrerequisitesBefore you begin, ensure you have the following installed:Flutter SDK (v3.0+)Python (v3.8+)A Groq API Key for the LLM analysis.💻 Installation & Setup1. Backend Setup (Python)The Python backend handles the web scraping logic to avoid CORS issues and client-side limitations.Bash# Navigate to the web directory
cd lib/web

# Create and activate a virtual environment
python -m venv venv
source venv/bin/activate  # On Windows use: venv\Scripts\activate

# Install the required dependencies
pip install -r requirements.txt

# Run the Flask app
python app.py
2. Frontend Setup (Flutter)Ensure your backend is running locally or deployed before starting the Flutter app.Bash# Return to the root project directory
cd ../..

# Install Flutter dependencies
flutter pub get

# Run the app on your connected device or emulator
flutter run
⚙️ ConfigurationTo enable the AI analysis features, you will need to configure your Groq API credentials.Open lib/services/groq_service.dart.  Inject your Groq API key into the service configuration (it is highly recommended to use .env files for production rather than hardcoding credentials).Ensure the Flutter app is pointing to the correct local or remote URL for your Python Flask scraper API.
