from flask import Flask, request, jsonify
from datetime import datetime

app = Flask(__name__)

@app.route("/", methods=["GET"])
def get_time_and_ip():
    forwarded_for_list = request.headers.getlist("X-Forwarded-For")

    if forwarded_for_list:
        all_ips = [ip.strip() for ip in forwarded_for_list[0].split(",")]
        user_ip = all_ips[0]
    else:
        all_ips = []
        user_ip = request.remote_addr

    response = {
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "user_ip": user_ip,
        "proxy_chain": all_ips if all_ips else None
    }
    return jsonify(response)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)  # nosemgrep: python.flask.security.audit.app-run-param-config.avoid_app_run_with_bad_host
