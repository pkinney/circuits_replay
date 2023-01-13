defmodule Replay do
  alias __MODULE__.Common

  def setup_uart(mock) do
    Common.create_table_if_needed()
    Common.setup_mock(mock, Circuits.UART)
  end

  def setup_i2c(mock) do
    Common.create_table_if_needed()
    Common.setup_mock(mock, Circuits.I2C)
  end

  def replay_i2c(sequence) do
    replay_id = Common.generate_replay_id()
    :ok = Common.insert_sequence(replay_id, sequence, %{})
    body = Replay.I2C.build_mock(replay_id)
    :ok = Common.inject_module(replay_id, Circuits.I2C, body)
    replay_id
  end

  def replay_uart(sequence) do
    replay_id = Common.generate_replay_id()
    :ok = Common.insert_sequence(replay_id, sequence, %{})
    body = Replay.UART.build_mock(replay_id)
    :ok = Common.inject_module(replay_id, Circuits.UART, body)
    replay_id
  end

  defdelegate assert_complete(replay_id), to: Common
  defdelegate await_complete(replay_id, timeout \\ 5_000), to: Common
end
