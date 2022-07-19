# Caefl
[WIP] Repo for the CAEFL paper

A simple example can be found [here](https://github.com/cocoa-xu/caefl_example).

## Basic Design
### Sensor
```elixir
defmodule CAEFL.Sensor do
  @doc """
  Sensor is expected to be initialised in this callback (if applicable).

  The `init_param` argument is forwarded from `GenServer.start/start_link`.

  The return value represents the state of current sensor.
  """
  @callback init_sensor(init_param :: term) ::
    {:ok, sensor_state :: term}
    | {:error, reason :: term}

  @doc """
  Read one sample from the sensor.
  """
  @callback read_data(sensor_state :: term) ::
    {:ok, data :: term, new_sensor_state :: term}
    | {:error, reason :: term}
end
```

Note that it's not required to use the `CAEFL.Sensor` module. Of course, there are `CAEFL.Sensor.start` and `CAEFL.Sensor.start_link` for different use cases.

If the sensor data is optional or the sensor is designed to be hot-swappable, then it's recommended to use `CAEFL.Sensor.start` to init the sensor.

If the sensor is critical for the agent, then perhaps `CAEFL.Sensor.start_link` could be used. If the sensor goes offline, then the whole system will try to restart. 

But this really depends on your design and how you prefer to handle sensor failures. It's complete okay to wait for that sensor to restart instead of linking it with the agent.

### Environment
```elixir
defmodule CAEFL.Environment do
  @doc """
  Get current environment tags.
  """
  def get_tags(state) do
    GenServer.call(state, :get_tags)
  end

  @doc """
  Return a list of current available environment sensors.
  """
  @callback environment_sensors(state :: term) ::
    {:ok, sensors :: term, new_state :: term}
    | {:error, error :: term}

  @doc """
  Transform the data from a certain environment sensor to sematic/numerical tags.
  """
  @callback transform(sensor_readings :: term) :: map()
end
```

### Agent
```elixir
defmodule CAEFL.SimpleAgent do
  @callback should_update_local_model?(self :: term()) ::
    {boolean(), new_self :: term()}
  @callback should_stop?(self :: term()) ::
    {true, reason :: atom(), reply :: term(), new_self :: term()}
    | false
  @callback update_local_tagged_model(model_param :: term(), env_tag :: term(), data :: term()) ::
    updated_model_param :: term()
  @callback get_initial_model(opts :: term()) ::
    model_param :: term()
  @callback should_push_local_tagged_model_to_parameter_server?(self :: term(), model_tag :: term(), model_param :: term()) ::
    should_push? :: boolean()
end
```

### ParameterServer
```elixir
defmodule CAEFL.ParameterServer do
  use GenServer
  @impl true
  def handle_cast({:model_updates, tags, updates},
                  state) do
    # store the uploaded updates by tags
  end
  @impl true
  def handle_call({:specialized_model, tags}, 
                  state), do: # follow Algo. 6
  @impl true
  def handle_call({:composite_model, tags}, 
                  state), do: # follow Algo. 7
end
```

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `caefl` to your list of dependencies in `mix.exs`:

```elixir
def deps do
[
{:caefl, "~> 0.1.0"}
]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/caefl>.

