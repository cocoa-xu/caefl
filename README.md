# Caefl
[WIP] Repo for the CAEFL paper

## Basic Design
### Sensor
```elixir
defmodule Sensor do
  @callback init(init_param :: term) :: 
            {:ok, sensor_state :: term}
            | {:error, reason :: term}
  @callback read_data(sensor_state :: term) :: 
            {:ok, data :: term}
            | {:error, reason :: term}
end
```

### Environment
```elixir
defmodule Environment do
  use GenServer
  @impl true
  def init(list_of_sensors)
  def get_tags(e) do: GenServer.call(e, :get_tags)
  @impl true
  def handle_call(:get_tags, _from, e)
  defp collect_data(e)
  defp transform(data_from_a_sensor)
  defp transform({type: :temperature, t: t}) do
    case t do
      t > 30 => {temperature: :hot}
      t < 0 => {temperature: :cold}
      _ => {temperature: :normal}
    end
  end
  defp transform(as_is), do: as_is
end
```

### NeuralNetwork
```elixir
defmodule NeuralNetwork do
  use GenServer
  @impl true
  def init(init_param)

  # prediction
  def predict_next(nn) do
    tags = Environment.get_tags(e)
    sample = Input.sample(input)
    GenServer.call(nn, 
      {:predict_one, tags, sample})
  end
  @impl true
  def handle_call({:predict_one, tags, sample},
                  _from, state) do
    predict(state, tags, sample)
  end
  defp predict(state, tags, sample)
  defp predict(state, {rain: true, fog: true},
              sample) do
    # use the specialized model for 
    # rainy and foggy environment.
  end
  defp predict(state, {snow: true}, sample) do
    # use the specialized model for snow
  end
  defp predict(state, _tags, sample) do
    # fallback to the normal model
  end
  
  # training
  def train(state) do
    GenServer.call(state, :train)
  end
    @impl true
  def handle_call(:train, _from, state) do
    {sample, label, tags} = 
        Input.training_sample(input)
    train(state, tags, sample, label)
  end
  defp train(state, tags, sample, label)
  defp train(state, {rain: true}, 
             sample, label) do
    # follow Algo. 5
  end
  defp train(state, _tags, sample, label) do
    # fallback to the normal model
  end
end
```

### ParameterServer
```elixir
defmodule ParameterServer do
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

