"""One regulator node of the (t,n)-threshold audit simulator.

Usage:  python node.py <node_id> <port>

Endpoints:
  GET  /health       -> {"ok": true}
  POST /share        -> receive this node's key share {"x": .., "y": ..}
  GET  /share        -> return this node's key share
  POST /ciphertext   -> receive the shared encrypted audit tag (for completeness)
"""
import argparse

from flask import Flask, jsonify, request

app = Flask(__name__)
STATE = {"share": None, "node_id": None, "ciphertext": None}


@app.get("/health")
def health():
    return jsonify({"ok": True})


@app.post("/share")
def receive_share():
    data = request.get_json(force=True)
    STATE["share"] = (int(data["x"]), int(data["y"]))
    STATE["node_id"] = data.get("node_id")
    return jsonify({"ok": True})


@app.get("/share")
def get_share():
    if STATE["share"] is None:
        return jsonify({"error": "no share distributed yet"}), 404
    return jsonify({"x": STATE["share"][0], "y": STATE["share"][1],
                    "node_id": STATE["node_id"]})


@app.post("/ciphertext")
def receive_ciphertext():
    data = request.get_json(force=True)
    STATE["ciphertext"] = data["ciphertext"]
    return jsonify({"ok": True})


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("node_id", type=int)
    parser.add_argument("port", type=int)
    args = parser.parse_args()
    STATE["node_id"] = args.node_id
    app.run(host="127.0.0.1", port=args.port, threaded=True)
