
test "try_graph_writer never waits while another request holds the writer" {
    with graph_writer() {
        with try_graph_writer() as got {
            assert not got;
        }
    }
    with try_graph_writer() as got {
        assert got;
    }
}

test "try_graph_writer releases the writer when it took it" {
    with try_graph_writer() as first {
        assert first;
    }
    with try_graph_writer() as second {
        assert second;
    }
}
