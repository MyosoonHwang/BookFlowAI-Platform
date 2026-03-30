from flask import Flask, jsonify
import socket

app = Flask(__name__)

@app.route('/')
def home():
    return f"Hello from ECS! Host: {socket.gethostname()}"

@app.route('/health')
def health():
    return jsonify({"status": "healthy"}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
