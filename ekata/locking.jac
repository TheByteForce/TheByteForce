"""Serialize all graph-changing requests across server processes."""
import os;
import fcntl;
import from contextlib { contextmanager }

@contextmanager
def graph_writer() -> any {
    path = os.path.join(os.getcwd(), ".jac", "ekata-writer.lock");
    os.makedirs(os.path.dirname(path), exist_ok=True);
    handle = open(path, "a");
    try {
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX);
        yield;
    } finally {
        fcntl.flock(handle.fileno(), fcntl.LOCK_UN);
        handle.close();
    }
}
