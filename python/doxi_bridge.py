import ast
import builtins
import contextlib
import io
import json
import sys
import traceback

FILENAME = "<doxi>"


def emit(payload):
    sys.stdout.write(json.dumps(payload, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def split_capture(text):
    if not text:
        return []
    return text.splitlines()


def flatten_traceback(parts):
    lines = []
    for part in parts:
        lines.extend(part.rstrip("\n").splitlines())
    return lines


class Bridge:
    def __init__(self):
        self.reset()

    def reset(self):
        self.globals = {
            "__name__": "__main__",
            "__package__": None,
        }

    def execute(self, source):
        if not source.strip():
            return {"chunks": []}

        try:
            tree = ast.parse(source, filename=FILENAME, mode="exec")
        except SyntaxError as exc:
            return {
                "chunks": [
                    {
                        "input_lines": source.splitlines(),
                        "stdout_lines": [],
                        "stderr_lines": [],
                        "result_lines": [],
                        "traceback_lines": self.format_syntax_error(exc),
                        "status": "error",
                    }
                ]
            }

        chunks = []

        for node in tree.body:
            segment = ast.get_source_segment(source, node)
            if segment is None:
                segment = self.slice_source(source, node.lineno, getattr(node, "end_lineno", node.lineno))

            stdout_buffer = io.StringIO()
            stderr_buffer = io.StringIO()
            result_lines = []
            traceback_lines = []
            status = "ok"

            try:
                with contextlib.redirect_stdout(stdout_buffer), contextlib.redirect_stderr(stderr_buffer):
                    if isinstance(node, ast.Expr):
                        expression = ast.Expression(body=node.value)
                        ast.fix_missing_locations(expression)
                        value = eval(compile(expression, FILENAME, "eval"), self.globals, self.globals)
                        if value is not None:
                            builtins._ = value
                            result_lines = repr(value).splitlines() or [repr(value)]
                    else:
                        module = ast.Module(body=[node], type_ignores=[])
                        ast.fix_missing_locations(module)
                        exec(compile(module, FILENAME, "exec"), self.globals, self.globals)
            except Exception:
                status = "error"
                traceback_lines = flatten_traceback(traceback.format_exception(*sys.exc_info()))

            chunks.append(
                {
                    "input_lines": segment.splitlines(),
                    "stdout_lines": split_capture(stdout_buffer.getvalue()),
                    "stderr_lines": split_capture(stderr_buffer.getvalue()),
                    "result_lines": result_lines,
                    "traceback_lines": traceback_lines,
                    "status": status,
                }
            )

            if status == "error":
                break

        return {"chunks": chunks}

    @staticmethod
    def format_syntax_error(exc):
        return ["Traceback (most recent call last):"] + flatten_traceback(
            traceback.format_exception_only(type(exc), exc)
        )

    @staticmethod
    def slice_source(source, start_line, end_line):
        lines = source.splitlines()
        return "\n".join(lines[start_line - 1 : end_line])


def handle_message(bridge, message):
    action = message.get("action")

    if action == "exec":
        return bridge.execute(message.get("code", ""))

    if action == "reset":
        bridge.reset()
        return {"status": "ok"}

    if action == "quit":
        return {"status": "bye"}

    raise ValueError(f"Unknown action: {action}")


def main():
    bridge = Bridge()

    for raw in sys.stdin:
        raw = raw.strip()
        if not raw:
            continue

        request_id = None

        try:
            message = json.loads(raw)
            request_id = message.get("id")
            result = handle_message(bridge, message)
            emit({"id": request_id, "ok": True, "result": result})

            if message.get("action") == "quit":
                return
        except Exception as exc:
            emit({"id": request_id, "ok": False, "error": f"Bridge error: {exc}"})


if __name__ == "__main__":
    main()
