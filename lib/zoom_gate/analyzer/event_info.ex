defmodule ZoomGate.Analyzer.EventRegistry.EventInfo do
  @moduledoc "Metadata for a single RWG event type."
  defstruct [:code, :name, :direction, :category, :body_fields, :description]

  @type t :: %__MODULE__{
          code: integer(),
          name: String.t(),
          direction: :client_to_server | :server_to_client,
          category: atom(),
          body_fields: [String.t()],
          description: String.t()
        }
end
