defmodule ZoomGate.Layouts do
  @moduledoc false
  use Phoenix.Component

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8"/>
      <meta name="viewport" content="width=device-width, initial-scale=1"/>
      <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
      <title>ZoomGate Dashboard</title>
      <script src="/assets/phoenix/phoenix.min.js"></script>
      <script src="/assets/phoenix_live_view/phoenix_live_view.min.js"></script>
      <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }

        body {
          font-family: system-ui, -apple-system, sans-serif;
          background: #1a1a2e;
          color: #e0e0e0;
          min-height: 100vh;
        }

        .dashboard {
          max-width: 1400px;
          margin: 0 auto;
          padding: 24px;
        }

        .header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          margin-bottom: 32px;
          padding-bottom: 16px;
          border-bottom: 1px solid #2a2a4e;
        }

        .header h1 {
          font-size: 24px;
          font-weight: 600;
          color: #ffffff;
        }

        .header-stats {
          display: flex;
          gap: 24px;
          align-items: center;
        }

        .stat-badge {
          display: flex;
          align-items: center;
          gap: 8px;
          background: #16213e;
          padding: 8px 16px;
          border-radius: 8px;
          font-size: 14px;
        }

        .stat-badge .value {
          font-weight: 700;
          font-size: 18px;
          color: #00d4aa;
          font-family: 'SF Mono', 'Menlo', monospace;
        }

        .pulse-dot {
          width: 8px;
          height: 8px;
          background: #00d4aa;
          border-radius: 50%;
          animation: pulse 2s infinite;
        }

        @keyframes pulse {
          0%, 100% { opacity: 1; }
          50% { opacity: 0.4; }
        }

        .grid {
          display: grid;
          grid-template-columns: 1fr;
          gap: 24px;
        }

        @media (min-width: 1024px) {
          .grid {
            grid-template-columns: 1fr 1fr;
          }
          .grid .sessions-section {
            grid-column: 1 / -1;
          }
        }

        .card {
          background: #16213e;
          border-radius: 12px;
          padding: 20px;
          border: 1px solid #2a2a4e;
        }

        .card-title {
          font-size: 16px;
          font-weight: 600;
          color: #ffffff;
          margin-bottom: 16px;
          display: flex;
          align-items: center;
          gap: 8px;
        }

        .card-title .count {
          background: #2a2a4e;
          color: #a0a0c0;
          padding: 2px 8px;
          border-radius: 12px;
          font-size: 12px;
          font-weight: 500;
        }

        /* Sessions Table */
        .sessions-table {
          width: 100%;
          border-collapse: collapse;
          font-size: 14px;
        }

        .sessions-table th {
          text-align: left;
          padding: 8px 12px;
          font-weight: 500;
          color: #a0a0c0;
          font-size: 12px;
          text-transform: uppercase;
          letter-spacing: 0.5px;
          border-bottom: 1px solid #2a2a4e;
        }

        .sessions-table td {
          padding: 10px 12px;
          border-bottom: 1px solid rgba(42, 42, 78, 0.5);
          vertical-align: middle;
        }

        .sessions-table tr:hover td {
          background: rgba(42, 42, 78, 0.3);
        }

        .meeting-id {
          font-family: 'SF Mono', 'Menlo', monospace;
          font-size: 13px;
          color: #80b0ff;
        }

        /* Status badge */
        .status {
          display: inline-block;
          padding: 3px 10px;
          border-radius: 12px;
          font-size: 12px;
          font-weight: 600;
          text-transform: uppercase;
          letter-spacing: 0.3px;
        }

        .status-active { background: rgba(0, 212, 170, 0.15); color: #00d4aa; }
        .status-connecting { background: rgba(255, 193, 7, 0.15); color: #ffc107; }
        .status-reconnecting { background: rgba(255, 193, 7, 0.15); color: #ffc107; }
        .status-initializing { background: rgba(255, 193, 7, 0.15); color: #ffc107; }
        .status-ended { background: rgba(255, 107, 107, 0.15); color: #ff6b6b; }
        .status-terminated { background: rgba(255, 107, 107, 0.15); color: #ff6b6b; }

        /* Health indicators */
        .health {
          display: flex;
          align-items: center;
          gap: 6px;
        }

        .health-dot {
          width: 8px;
          height: 8px;
          border-radius: 50%;
          flex-shrink: 0;
        }

        .health-green { background: #00d4aa; }
        .health-yellow { background: #ffc107; }
        .health-red { background: #ff6b6b; }

        .health-text {
          font-size: 12px;
          color: #a0a0c0;
          font-family: 'SF Mono', 'Menlo', monospace;
        }

        /* Count badges in table */
        .count-badge {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          min-width: 28px;
          padding: 2px 8px;
          border-radius: 12px;
          font-family: 'SF Mono', 'Menlo', monospace;
          font-size: 13px;
          font-weight: 600;
        }

        .count-participants {
          background: rgba(0, 212, 170, 0.15);
          color: #00d4aa;
        }

        .count-waiting {
          background: rgba(255, 193, 7, 0.15);
          color: #ffc107;
        }

        .btn {
          padding: 6px 14px;
          border-radius: 6px;
          border: none;
          font-size: 12px;
          font-weight: 600;
          cursor: pointer;
          transition: all 0.15s;
        }

        .btn-danger {
          background: rgba(255, 107, 107, 0.15);
          color: #ff6b6b;
          border: 1px solid rgba(255, 107, 107, 0.3);
        }

        .btn-danger:hover {
          background: rgba(255, 107, 107, 0.3);
        }

        /* Participant detail */
        .participant-detail {
          margin-top: 8px;
          padding: 12px;
          background: rgba(26, 26, 46, 0.5);
          border-radius: 8px;
          font-size: 13px;
        }

        .participant-detail .section-label {
          font-size: 11px;
          color: #a0a0c0;
          text-transform: uppercase;
          letter-spacing: 0.5px;
          margin-bottom: 6px;
        }

        .participant-list {
          display: flex;
          flex-wrap: wrap;
          gap: 6px;
        }

        .participant-chip {
          background: #2a2a4e;
          padding: 3px 10px;
          border-radius: 12px;
          font-size: 12px;
        }

        .participant-chip.waiting {
          background: rgba(255, 193, 7, 0.1);
          border: 1px solid rgba(255, 193, 7, 0.2);
        }

        /* Webhook Events Feed */
        .events-feed {
          max-height: 500px;
          overflow-y: auto;
          scrollbar-width: thin;
          scrollbar-color: #2a2a4e #16213e;
        }

        .events-feed::-webkit-scrollbar {
          width: 6px;
        }

        .events-feed::-webkit-scrollbar-track {
          background: #16213e;
        }

        .events-feed::-webkit-scrollbar-thumb {
          background: #2a2a4e;
          border-radius: 3px;
        }

        .event-item {
          padding: 10px 12px;
          border-bottom: 1px solid rgba(42, 42, 78, 0.3);
          font-size: 13px;
          display: flex;
          gap: 12px;
          align-items: flex-start;
        }

        .event-item:hover {
          background: rgba(42, 42, 78, 0.2);
        }

        .event-time {
          font-family: 'SF Mono', 'Menlo', monospace;
          font-size: 11px;
          color: #666680;
          white-space: nowrap;
          flex-shrink: 0;
          min-width: 70px;
        }

        .event-type {
          font-weight: 600;
          font-size: 12px;
          padding: 2px 8px;
          border-radius: 4px;
          white-space: nowrap;
          flex-shrink: 0;
        }

        .event-type-waiting { background: rgba(255, 193, 7, 0.15); color: #ffc107; }
        .event-type-joined { background: rgba(0, 212, 170, 0.15); color: #00d4aa; }
        .event-type-left { background: rgba(255, 107, 107, 0.15); color: #ff6b6b; }
        .event-type-admitted { background: rgba(128, 176, 255, 0.15); color: #80b0ff; }
        .event-type-raw { background: rgba(160, 160, 192, 0.15); color: #a0a0c0; }

        .event-detail {
          color: #c0c0d0;
          flex: 1;
          min-width: 0;
        }

        .event-meeting {
          font-family: 'SF Mono', 'Menlo', monospace;
          font-size: 11px;
          color: #80b0ff;
        }

        .empty-state {
          text-align: center;
          padding: 40px 20px;
          color: #666680;
          font-size: 14px;
        }

        .restart-badge {
          font-family: 'SF Mono', 'Menlo', monospace;
          font-size: 12px;
          color: #ff6b6b;
        }
      </style>
    </head>
    <body>
      {@inner_content}
      <script>
        let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
        let liveSocket = new LiveView.LiveSocket("/live", Phoenix.Socket, {
          params: {_csrf_token: csrfToken}
        });
        liveSocket.connect();
      </script>
    </body>
    </html>
    """
  end
end
