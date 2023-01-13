defmodule Replay.I2C do
  alias Replay.Common

  def build_mock(replay_id, opts \\ []) do
    devices =
      Keyword.get(
        opts,
        :devices,
        Replay.Common.sequence(replay_id)
        |> devices_from_sequence()
      )

    bus_names = Keyword.get(opts, :busses, ["i2c-1"])
    i2c_ref = make_ref() |> :erlang.ref_to_list()

    quote do
      def bus_names(), do: unquote(bus_names)
      def detect_devices(), do: unquote(devices)

      def device_present?(_i2c, address), do: detect_devices() |> Enum.member?(address)

      def open(bus_name) do
        {:ok, unquote(i2c_ref) |> :erlang.list_to_ref()}
      end

      def read(_, address, bytes_to_read, _opts \\ []) do
        case Common.step(unquote(replay_id)) do
          {:read, ^address, resp} when byte_size(resp) == bytes_to_read -> {:ok, resp}
          nil -> throw(sequence_complete({:read, address, bytes_to_read}))
          step -> throw(out_of_sequence({:read, address, bytes_to_read}, step))
        end
      end

      def read!(i2c_bus, address, bytes_to_read, opts \\ []) do
        {:ok, resp} = read(i2c_bus, address, bytes_to_read, opts)
        resp
      end

      def write(_, address, data, _opts \\ []) do
        case Common.step(unquote(replay_id)) do
          {:write, ^address, ^data} -> :ok
          nil -> throw(sequence_complete({:write, address, data}))
          step -> throw(out_of_sequence({:write, address, data}, step))
        end
      end

      def write!(i2c_bus, address, data, opts \\ []) do
        :ok = write(i2c_bus, address, data, opts)
      end

      def write_read(_, address, write, bytes, _ \\ []) do
        case Common.step(unquote(replay_id)) do
          {:write_read, ^address, ^write, resp} when byte_size(resp) == bytes -> {:ok, resp}
          nil -> throw(sequence_complete({:write_read, address, write, bytes}))
          step -> throw(out_of_sequence({:write_read, address, write, bytes}, step))
        end
      end

      def write_read!(i2c_bus, address, write_data, bytes_to_read, opts \\ []) do
        {:ok, resp} = write_read(i2c_bus, address, write_data, bytes_to_read, opts)
        resp
      end

      defp out_of_sequence(actual, expected) do
        "[Out of Sequence] \n   - expected: #{inspect(expected, base: :hex)} \n   - got: #{inspect(actual, base: :hex)}"
      end

      defp sequence_complete(actual) do
        "[Out of Sequence] Replay is complete but received #{inspect(actual, base: :hex)}"
      end
    end
  end

  defp devices_from_sequence(sequence) do
    sequence |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
  end
end
