defmodule Replay.UARTMimicTest do
  use ExUnit.Case, async: false

  defp uart(), do: Resolve.resolve(Circuits.UART)

  setup do
    Replay.setup_uart(:mimic)
  end

  test "Successful sequence" do
    replay =
      Replay.replay_uart([
        {:write, "S0 T5"},
        {:read, "ACK"},
        {:write, "V34"},
        {:write, "R5531"},
        {:read, <<0xFF, 0xFF, 0xFE>>}
      ])

    {:ok, uart} = uart().start_link()
    :ok = uart().open(uart, "ttyAMA0", active: false)
    uart().write(uart, "S0 T5")
    {:ok, "ACK"} = uart().read(uart)
    uart().write(uart, "V34")
    uart().write(uart, "R5531")
    {:ok, <<0xFF, 0xFF, 0xFE>>} = uart().read(uart)

    Replay.assert_complete(replay)
  end

  test "out of sequence write" do
    _replay =
      Replay.replay_uart([
        {:write, "S0 T5"},
        {:read, "ACK"}
      ])

    {:ok, uart} = uart().start_link()
    :ok = uart().open(uart, "ttyAMA0", active: false)
    uart().write(uart, "S0 T5")

    assert catch_throw(uart().write(uart, "S0 T5"))
  end

  test "out of sequence read" do
    _replay =
      Replay.replay_uart([
        {:write, "S0 T5"},
        {:read, "ACK"},
        {:write, "A38"}
      ])

    {:ok, uart} = uart().start_link()
    :ok = uart().open(uart, "ttyAMA0", active: false)
    uart().write(uart, "S0 T5")
    uart().read(uart)

    assert catch_throw(uart().read(uart))
  end

  test "write after complete" do
    _replay =
      Replay.replay_uart([
        {:write, "S0 T5"},
        {:read, "ACK"}
      ])

    {:ok, uart} = uart().start_link()
    :ok = uart().open(uart, "ttyAMA0", active: false)
    uart().write(uart, "S0 T5")
    {:ok, "ACK"} = uart().read(uart)

    assert catch_throw(uart().write(uart, "A38"))
  end

  test "read after complete" do
    _replay =
      Replay.replay_uart([
        {:write, "S0 T5"},
        {:read, "ACK"}
      ])

    {:ok, uart} = uart().start_link()
    :ok = uart().open(uart, "ttyAMA0", active: false)
    uart().write(uart, "S0 T5")
    {:ok, "ACK"} = uart().read(uart)

    assert catch_throw(uart().read(uart))
  end

  test "failed replay completion" do
    replay =
      Replay.replay_uart([
        {:write, "S0 T5"},
        {:read, "ACK"}
      ])

    {:ok, uart} = uart().start_link()
    :ok = uart().open(uart, "ttyAMA0", active: false)
    uart().write(uart, "S0 T5")

    assert catch_throw(Replay.assert_complete(replay))
  end

  test "await_complete should wait until the sequence is completed" do
    replay =
      Replay.replay_uart([
        {:write, "S0 T5"},
        {:read, "ACK"}
      ])

    {:ok, uart} = uart().start_link()
    :ok = uart().open(uart, "ttyAMA0", active: false)
    uart().write(uart, "S0 T5")

    Task.async(fn ->
      :timer.sleep(150)
      uart().read(uart)
    end)

    Replay.await_complete(replay)
    Replay.assert_complete(replay)
  end

  test "await_complete should throw if the sequence is not completed in time" do
    replay =
      Replay.replay_uart([
        {:write, "S0 T5"},
        {:read, "ACK"}
      ])

    {:ok, uart} = uart().start_link()
    :ok = uart().open(uart, "ttyAMA0", active: false)
    uart().write(uart, "S0 T5")

    Task.async(fn ->
      :timer.sleep(150)
      uart().read(uart)
    end)

    assert catch_throw(Replay.await_complete(replay, 50))
  end

  test "active mode" do
    replay =
      Replay.replay_uart([
        {:write, "S0 T5"},
        {:read, "ACK"},
        {:read, "D0"}
      ])

    {:ok, uart} = uart().start_link()
    :ok = uart().open(uart, "ttyAMA0")
    uart().write(uart, "S0 T5")
    assert_received({:circuits_uart, "ttyAMA0", "ACK"})
    assert_received({:circuits_uart, "ttyAMA0", "D0"})
    Replay.assert_complete(replay)
  end
end
