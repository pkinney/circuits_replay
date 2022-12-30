# Circuits.Replay

A testing library that can mock all of the [Circuits]{https://elixir-circuits.github.io/) libraries to 
step through and assert a sequence of calls and messages.


## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `replay` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:replay, "~> 0.1.0"}
  ]
end
```

## Usage

To mock each of the Circuits libraries, this tool uses [Resolve](), an extremely lightweight mocking
library.  Without your project, use Resolve's `resolve/1` function to determin the module to call:


```elixit


```

### UART

```elixir
 defp uart(), do: Resolve.resolve(Circuits.UART)

  test "Successful sequence" do
    replay =
      Replay.UART.replay([
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

    Replay.UART.assert_complete(replay)
  end
```

### I2C

### GPIO

### SPI

Not implemented yet
