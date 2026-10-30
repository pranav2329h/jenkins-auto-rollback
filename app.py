
import os
from flask import Flask, jsonify

app = Flask(__name__)

APP_VERSION = os.getenv("APP_VERSION", "v1")


@app.route("/")
def home():
    return jsonify({
        "application": "Auto-Rollback Demo",
        "version": APP_VERSION,
        "message": "Application is running"
    }), 200


@app.route("/health")
def health():
    return jsonify({
        "status": "healthy",
        "version": APP_VERSION
    }), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
