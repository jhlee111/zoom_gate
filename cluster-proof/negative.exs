# Run on the gs_net stand-in when it was booted with a DIFFERENT RELEASE_COOKIE
# than zoom_gate. Distributed Erlang authenticates solely by cookie, so the
# nodes must NOT connect. Wait out libcluster's retry window, then assert the
# peer never joined. Returns the marker on success; raises if a mismatched
# cookie still connected (which would be a security failure).
peer = :"zoom_gate@zoom-gate.bnb"
Process.sleep(8000)

if peer in Node.list() do
  raise("SECURITY FAIL: connected to #{inspect(peer)} despite cookie mismatch")
end

IO.puts("COOKIE_NEGATIVE_OK self=#{node()} nodes=#{inspect(Node.list())}")
