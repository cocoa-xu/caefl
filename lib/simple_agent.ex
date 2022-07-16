defmodule CAEFL.SimpleAgent do
  defmacro __using__(_opts) do
    quote do
      use GenServer
      @behaviour CAEFL.SimpleAgent
      require Logger

      defstruct [
        :ps,
        :ps_timeout,
        :data_sensors,
        :environment,
        :data_waiting_for_model_param,
        :sampled_data,
        :models,
        :serialize,
        :deserialize,
        :opts
      ]
      alias __MODULE__, as: T

      def start_link(ps_ip, ps_port, ps_timeout, data_sensors, environment, serialize, deserialize, opts \\ []) do
        {:ok, ps} = CAEFL.ParameterServer.start(ps_ip, ps_port, serialize, deserialize)
        GenServer.start_link(__MODULE__, %T{
          serialize: serialize,
          deserialize: deserialize,
          ps: ps,
          ps_timeout: ps_timeout,
          data_sensors: data_sensors,
          environment: environment,
          data_waiting_for_model_param: [],
          sampled_data: [],
          models: [],
          opts: opts
        }, opts)
      end

      def start(ps_ip, ps_port, ps_timeout, data_sensors, environment, serialize, deserialize, opts \\ []) do
        {:ok, ps} = CAEFL.ParameterServer.start(ps_ip, ps_port, serialize, deserialize)
        GenServer.start(__MODULE__, %T{
          serialize: serialize,
          deserialize: deserialize,
          ps: ps,
          ps_timeout: ps_timeout,
          data_sensors: data_sensors,
          environment: environment,
          data_waiting_for_model_param: [],
          sampled_data: [],
          models: [],
          opts: opts
        }, opts)
      end

      @impl true
      def init(agent=%T{}) do
        {:ok, agent}
      end

      @impl true
      def handle_call({:sample_once, peek_only}, _from, self=%T{}) do
        samples = Enum.map(self.data_sensors, fn ds ->
          CAEFL.Sensor.read_data(ds)
        end)
        tags = CAEFL.Environment.get_tags(self.environment)
        sampled_data =
          if !peek_only do
            [%{data: samples, tag: tags} | self.sampled_data]
          else
            self.sampled_data
          end
        {:reply, %{data: samples, tag: tags}, %T{self | sampled_data: sampled_data}}
      end

      @impl true
      def handle_call({:update_local_model, agent}, _from, self=%T{opts: opts, data_waiting_for_model_param: list}) do
        {should_update?, self} = should_update_local_model?(self)
        self =
          if should_update? do
            agg = aggregate_samples(self.sampled_data)

            {tags, acc} =
              Enum.map(agg, fn {env_tag, data} ->
                find_and_update_local_tagged_model(agent, self, env_tag, data)
              end)
              |> Enum.filter(fn v ->
                case v do
                  {:remote, _, _} ->  true
                  _ -> false
                end
              end)
              |> Enum.reduce({[], []}, fn {:remote, env_filter, data}, {tags, acc} ->
                {[env_filter | tags], [%{tag: env_filter, data: data} | acc]}
              end)
            Enum.each(tags, fn env_filter ->
              CAEFL.ParameterServer.get_latest_model(agent, self.ps, env_filter, true)
            end)
            %T{self | sampled_data: [], data_waiting_for_model_param: list ++ acc}
          else
            self
          end

          case should_stop?(self) do
            {true, reason, reply, self} ->
              {:stop, reason, reply, self}
            false ->
              {:reply, :ok, self}
          end
      end

      @impl true
      def handle_cast({:update_local_tagged_model_done, callback_pid, model_tag, updated_model_param}, self) do
        Logger.debug("update_local_tagged_model_done: #{inspect(model_tag)}")
        if should_push_local_tagged_model_to_parameter_server?(self, model_tag, updated_model_param) do
          CAEFL.ParameterServer.push_tagged_model(callback_pid, self.ps, model_tag, updated_model_param)
        end
        {:noreply, self}
      end

      @impl true
      def handle_cast({:consume_data_waiting_for_model_param, agent}, self=%T{data_waiting_for_model_param: list}) do
        if Enum.count(list) > 0 do
          agg = aggregate_samples(list)
          {tags, acc} =
            Enum.map(agg, fn {env_tag, data} ->
              find_and_update_local_tagged_model(agent, self, env_tag, data)
            end)
            |> Enum.filter(fn v ->
              case v do
                {:remote, _, _} ->  true
                _ -> false
              end
            end)
            |> Enum.reduce({[], []}, fn {:remote, env_filter, data}, {tags, acc} ->
              {[env_filter | tags], [%{tag: env_filter, data: data} | acc]}
            end)
          Enum.each(tags, fn env_filter ->
            CAEFL.ParameterServer.get_latest_model(agent, self.ps, env_filter, true)
          end)
          {:noreply, %T{self | data_waiting_for_model_param: acc}}
        else
          {:noreply, self}
        end
      end

      @impl true
      def handle_cast({action=:fetch_model, reply}, self) do
        new_self =
          case reply do
            {:ok, query={_, env_filter, _, callback_pid}, model_param} ->
              Logger.debug("#{action} ok, query: #{inspect(query)}")
              index =
                Enum.find_index(self.models, fn %{tag: model_tag} ->
                  model_tag == env_filter
                end)
              models =
                if index == nil do
                  [%{tag: env_filter, model_param: model_param} | self.models]
                else
                  models = List.delete_at(self.models, index)
                  [%{tag: env_filter, model_param: model_param} | self.models]
                end
              %T{self | models: models}
            {:error, query={_, env_filter, _, callback_pid}, reason} ->
              Logger.debug("#{action} failed, query: #{inspect(query)}, reason: #{reason}")
              model_param = get_initial_model(self.opts)
              index =
                Enum.find_index(self.models, fn %{tag: model_tag} ->
                  model_tag == env_filter
                end)
              models =
                if index == nil do
                  [%{tag: env_filter, model_param: model_param} | self.models]
                else
                  models = List.delete_at(self.models, index)
                  [%{tag: env_filter, model_param: model_param} | self.models]
                end
              %T{self | models: models}
            _ ->
              Logger.debug("#{action} received unrecognised reply: #{inspect(reply)}")
              self
          end
        {:noreply, new_self}
      end

      def sample_once(agent, peek_only \\ false) do
        GenServer.call(agent, {:sample_once, peek_only})
      end

      def update_local_model(agent) do
        GenServer.call(agent, {:update_local_model, agent})
      end

      def start_runloop(agent, opts \\ []) do
        spawn(__MODULE__, :runloop, [agent, opts])
      end

      def runloop(agent, opts) do
        _ = sample_once(agent)
        # GenServer.cast(agent, {:consume_data_waiting_for_model_param, agent})
        if update_local_model(agent) != :stop do
          runloop(agent, opts)
        end
      end

      def aggregate_samples(sampled_data) do
        agg =
          Enum.reduce(sampled_data, %{}, fn %{tag: tag, data: data}, agg ->
            str_tag = Base.encode64(:erlang.term_to_binary(tag))
            Map.update(agg, str_tag, [data], fn d -> [data | d] end)
          end)
        Enum.map(Map.keys(agg), fn tag ->
          {:erlang.binary_to_term(Base.decode64!(tag)), Map.get(agg, tag)}
        end)
      end

      def find_and_update_local_tagged_model(callback_pid, self, env_tag, data) do
        case get_local_tagged_model(callback_pid, self, env_tag, data, true) do
          {:local, model_tag, model_param} ->
            Logger.debug("Found local model that matches tags: #{inspect(env_tag)}")
            do_update_local_tagged_model(callback_pid, self, model_tag, model_param, env_tag, data)
            :local
          :maybe_request_remote_model_param ->
            Logger.debug("Requesting remote model with tags: #{inspect(env_tag)}...")
            {:remote, env_tag, data}
        end
      end

      def get_local_tagged_model(callback_pid, self=%T{data_waiting_for_model_param: list}, env_filter, data, true) do
        index =
          Enum.find_index(self.models, fn %{tag: model_tag} ->
            model_tag == env_filter
          end)
        if index == nil do
          :maybe_request_remote_model_param
        else
          %{tag: model_tag, model_param: model_param} = Enum.at(self.models, index)
          {:local, model_tag, model_param}
        end
      end

      def do_update_local_tagged_model(callback_pid, self, model_tag, model_param, env_tag, data) do
        updated_model_param = update_local_tagged_model(model_param, env_tag, data)
        Logger.debug("local model updated: #{inspect(model_tag)}")
        GenServer.cast(callback_pid, {:update_local_tagged_model_done, callback_pid, model_tag, updated_model_param})
      end
    end
  end

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
