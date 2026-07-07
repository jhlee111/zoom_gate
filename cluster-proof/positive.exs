# Run via `bin/zoom_gate rpc` on the gs_net stand-in node. Proves the cluster is
# up and the two cross-node primitives gs_net will use both work. The final
# expression returns the success marker (rpc prints it) so the harness can grep
# it without relying on IO forwarding; any failure raises before the marker.
peer = :"zoom_gate@zoom-gate.bnb"

connected? =
  Enum.reduce_while(1..40, false, fn _, _ ->
    if peer in Node.list() do
      {:halt, true}
    else
      Process.sleep(500)
      {:cont, false}
    end
  end)

unless connected?, do: raise("peer #{inspect(peer)} not connected; Node.list=#{inspect(Node.list())}")
:pong = :net_adm.ping(peer)

# (1) cross-node call into ZoomGate's own code — the lookup gs_net's transport
# uses to find a session on the zoom_gate node.
nil = :erpc.call(peer, ZoomGate.Session, :whereis, ["proof-no-session"])

# (2) cross-node Phoenix.PubSub — the event path back to gs_net. Subscribe here,
# broadcast on the peer, assert delivery.
:ok = Phoenix.PubSub.subscribe(ZoomGate.PubSub, "proof:1")
:ok = :erpc.call(peer, Phoenix.PubSub, :broadcast, [ZoomGate.PubSub, "proof:1", {:hello, node()}])

receive do
  {:hello, _from} -> :ok
after
  5000 -> raise("no cross-node PubSub message received within 5s")
end

IO.puts("CLUSTER_PROOF_OK self=#{node()} peer_reached=#{inspect(peer)} nodes=#{inspect(Node.list())}")
