defmodule Replay.UARTTest do
  use ExUnit.Case

  import Resolve

  test "Successful sequence" do
    replay = Replay.UART.replay([{:write, "S0 T5"}, {:read, "ACK"}])

    {:ok, uart} = resolve(Circuits.UART).start_link()
    :ok = resolve(Circuits.UART).open(uart, "ttyAMA0", active: false)
    resolve(Circuits.UART).write(uart, "S0 T5")
    {:ok, "ACK"} = Resolve.resolve(Circuits.UART).read(uart)

    Replay.UART.assert_complete(replay)
  end

  test "out of sequence write" do
    _replay = Replay.UART.replay([{:write, "S0 T5"}, {:read, "ACK"}])

    {:ok, uart} = resolve(Circuits.UART).start_link()
    :ok = resolve(Circuits.UART).open(uart, "ttyAMA0", active: false)
    resolve(Circuits.UART).write(uart, "S0 T5")

    assert catch_throw(resolve(Circuits.UART).write(uart, "S0 T5"))
  end

  test "out of sequence read" do
    _replay = Replay.UART.replay([{:write, "S0 T5"}, {:read, "ACK"}, {:write, "A38"}])

    {:ok, uart} = resolve(Circuits.UART).start_link()
    :ok = resolve(Circuits.UART).open(uart, "ttyAMA0", active: false)
    resolve(Circuits.UART).write(uart, "S0 T5")
    resolve(Circuits.UART).read(uart)

    assert catch_throw(resolve(Circuits.UART).read(uart))
  end

  test "write after complete" do
    _replay = Replay.UART.replay([{:write, "S0 T5"}, {:read, "ACK"}])

    {:ok, uart} = resolve(Circuits.UART).start_link()
    :ok = resolve(Circuits.UART).open(uart, "ttyAMA0", active: false)
    resolve(Circuits.UART).write(uart, "S0 T5")
    {:ok, "ACK"} = resolve(Circuits.UART).read(uart)

    assert catch_throw(resolve(Circuits.UART).write(uart, "A38"))
  end

  test "read after complete" do
    _replay = Replay.UART.replay([{:write, "S0 T5"}, {:read, "ACK"}])

    {:ok, uart} = resolve(Circuits.UART).start_link()
    :ok = resolve(Circuits.UART).open(uart, "ttyAMA0", active: false)
    resolve(Circuits.UART).write(uart, "S0 T5")
    {:ok, "ACK"} = resolve(Circuits.UART).read(uart)

    assert catch_throw(resolve(Circuits.UART).read(uart))
  end

  test "failed replay completion" do
    replay = Replay.UART.replay([{:write, "S0 T5"}, {:read, "ACK"}])

    {:ok, uart} = resolve(Circuits.UART).start_link()
    :ok = resolve(Circuits.UART).open(uart, "ttyAMA0", active: false)
    resolve(Circuits.UART).write(uart, "S0 T5")

    assert catch_throw(Replay.UART.assert_complete(replay))
  end

  test "active mode" do
    replay = Replay.UART.replay([{:write, "S0 T5"}, {:read, "ACK"}, {:read, "D0"}])

    {:ok, uart} = resolve(Circuits.UART).start_link()
    :ok = resolve(Circuits.UART).open(uart, "ttyAMA0")
    resolve(Circuits.UART).write(uart, "S0 T5")
    assert_received({:circuits_uart, "ttyAMA0", "ACK"})
    assert_received({:circuits_uart, "ttyAMA0", "D0"})
    Replay.UART.assert_complete(replay)
  end
end
