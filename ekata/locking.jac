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

# Like graph_writer, but never waits: yields False when another request
# holds the lock, so a caller can answer from the current state instead.
@contextmanager
def try_graph_writer() -> any {
    path = os.path.join(os.getcwd(), ".jac", "ekata-writer.lock");
    os.makedirs(os.path.dirname(path), exist_ok=True);
    handle = open(path, "a");
    got = False;
    try {
        try {
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB);
            got = True;
        } except BlockingIOError {
            got = False;
        }
        yield got;
    } finally {
        if got {
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN);
        }
        handle.close();
    }
}
