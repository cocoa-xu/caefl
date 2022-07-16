defmodule CAEFL.ParameterServer do
  use GenServer
  defstruct [:serialize, :deserialize, :models, :tagged_model_updates, :ip, :port, :save, :socket, :role, :receiving_queue]
  alias __MODULE__, as: T
  require Logger

  # GenServer

  @spec start(maybe_improper_list, any, any, any, any, any) ::
          :ignore | {:error, any} | {:ok, pid}
  def start(saved_model_params, ip, port, save, serialize, deserialize) when is_list(saved_model_params) do
    GenServer.start(__MODULE__, {saved_model_params, ip, port, save, serialize, deserialize, :server})
  end

  def start(ps_ip, ps_port, serialize, deserialize) when is_tuple(ps_ip) do
    GenServer.start(__MODULE__, {ps_ip, ps_port, serialize, deserialize, :client})
  end

  def start_link(saved_model_params, ip, port, save, serialize, deserialize) when is_list(saved_model_params) do
    GenServer.start_link(__MODULE__, {saved_model_params, ip, port, save, serialize, deserialize, :server})
  end

  def start_link(ps_ip, ps_port, serialize, deserialize) when is_tuple(ps_ip) do
    GenServer.start_link(__MODULE__, {ps_ip, ps_port, serialize, deserialize, :client})
  end

  @impl true
  def init({saved_model_params, ip, port, save, serialize, deserialize, :server}) do
    {:ok, socket} = :gen_udp.open(port, [:binary, {:reuseaddr, true}, {:active, true}, {:ip, ip}])

    {:ok, %T{
      serialize: serialize,
      deserialize: deserialize,
      models: saved_model_params,
      tagged_model_updates: [],
      ip: ip,
      port: port,
      save: save,
      socket: socket,
      role: :server,
      receiving_queue: %{}
    }}
  end

  @impl true
  def init({ps_ip, ps_port, serialize, deserialize, :client}) do
    {:ok, socket} = :gen_udp.open(0, [:binary, {:reuseaddr, true}, {:active, true}])
    {:ok, %T{
      serialize: serialize,
      deserialize: deserialize,
      models: [],
      tagged_model_updates: [],
      ip: ps_ip,
      port: ps_port,
      save: nil,
      socket: socket,
      role: :client,
      receiving_queue: %{}
    }}
  end

  def process_query(ip, port, ps=%T{role: :server}, query={:fetch_model, env_filter, strict?, _}) do
    Logger.debug("Message from ip: #{inspect(ip)}, port: #{port}, msg: #{inspect({env_filter, strict?})}")
    case find_model(ps, env_filter, strict?) do
      {:ok, %{model_param: model_param}} ->
        Logger.debug("Found model corresponds to the request tag: #{inspect(env_filter)}")
        %{reply: {:ok, query, model_param}}
      :not_found ->
        err_msg = "No model satisfies the request: #{inspect(env_filter)}"
        Logger.debug(err_msg)
        %{reply: {:error, query, err_msg}}
    end
  end

  def process_query(ip, port, ps=%T{role: :server}, query={:push_tagged_model, env_filter, updated_model_param, _}) do
    Logger.debug("Updated tagged model parameters from ip: #{inspect(ip)}, port: #{port}, msg: #{inspect(env_filter)}")
    ps = process_updated_model_param(ps, env_filter, updated_model_param)
    %{reply: {:ok, query, "updated"}, update_self: ps}
  end

  def process_query(ip, port, _ps=%T{role: :server}, query) do
    Logger.debug("Received unrecognised message from ip: #{inspect(ip)}, port: #{port}")
    %{reply: {:error, query, "unrecognised message"}}
  end

  def describe_receiving_queue(receiving_queue) do
    waiting_keys = Map.keys(receiving_queue)
    Enum.each(waiting_keys, fn wk ->
      IO.puts("waiting for more frag for #{wk}")
    end)
  end

  def assemble_frags(socket, ip, port, data, ps=%T{receiving_queue: receiving_queue}, send_err_msg \\ true) do
    frag =
      try do
        :erlang.binary_to_term(data)
      rescue
        _ ->
          Logger.debug("Illegal message from ip: #{inspect(ip)}, port: #{port} (binary_to_term)")
          %{}
      end

    case frag do
      %{metainfo: true} ->
        identifier = make_identifier(frag)
        describe_receiving_queue(receiving_queue)
        %T{ps | receiving_queue: Map.put(receiving_queue, identifier, %{src: [ip: ip, port: port], metainfo: frag, data: %{}})}
      %{id: _id, frag: _frag, index: _index, num_frags: _num_frags} ->
        case update_receiving_queue(ip, port, receiving_queue, frag) do
          {:ok, receiving_queue} ->
            %T{ps | receiving_queue: receiving_queue}
          {:done, receiving_queue, query} ->
            message =
              try do
                :erlang.binary_to_term(query)
              rescue
                _ ->
                  Logger.debug("Illegal message from ip: #{inspect(ip)}, port: #{port}")
                  {}
              end
            ps = %T{ps | receiving_queue: receiving_queue}
            {ps, message}
          {:error, receiving_queue, msg} ->
            ps = %T{ps | receiving_queue: receiving_queue}
            if send_err_msg do
              send_message(ps, ip, port, :erlang.term_to_binary(msg), socket)
            end
            ps
        end
      _ ->
        ps
    end
  end

  # Role Server
  @impl true
  def handle_info({:udp, socket, ip, port, data}, ps=%T{role: :server}) do
    new_ps =
      case assemble_frags(socket, ip, port, data, ps) do
        {ps, query} ->
          reply = process_query(ip, port, ps, query)
          Logger.debug("got query: #{inspect(query)}")
          new_ps = Map.get(reply, :update_self, ps)
          send_message(ps, ip, port, :erlang.term_to_binary(reply[:reply]), socket)
          new_ps
        ps ->
          ps
      end
    {:noreply, new_ps}
  end

  # Role Client
  @impl true
  def handle_info({:udp, socket, ip, port, data}, ps=%T{role: :client}) do
    new_ps =
      case assemble_frags(socket, ip, port, data, ps, false) do
        {ps, reply} ->
          process_reply(ip, port, ps, reply)
          ps
        ps ->
          ps
      end
    {:noreply, new_ps}
  end

  def process_reply(ip, port, %T{role: :client}, reply={status, {:fetch_model, _, _, callback_pid}, _}) when status == :ok or status == :error do
    Logger.debug("Received fetch_model reply from ip: #{inspect(ip)}, port: #{port}")
    if Process.alive?(callback_pid) do
      GenServer.cast(callback_pid, {:fetch_model, reply})
    end
  end

  def process_reply(ip, port, %T{role: :client}, _reply) do
    Logger.debug("Received illegal message from ip: #{inspect(ip)}, port: #{port}")
  end

  def make_identifier(_frag=%{id: id, num_frags: num_frags}) do
    %{id: id, num_frags: num_frags}
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16()
  end

  def update_receiving_queue(ip, port, receiving_queue, frag) do
    identifier = make_identifier(frag)
    current = Map.get(receiving_queue, identifier)
    if current == nil do
      {:error, receiving_queue, "illegal operation"}
    else
      with %{id: id, frag: frag_data, index: index, num_frags: num_frags} <- frag,
           %{src: [ip: ^ip, port: ^port], metainfo: %{id: ^id, num_frags: ^num_frags}, data: data} <- current do

        updated_data =
          if Map.get(data, index) == nil do
            Map.put_new(data, index, frag_data)
          else
            data
          end

        current = Map.update!(current, :data, fn _ -> updated_data end)
        if Enum.count(Map.keys(updated_data)) == num_frags do
          receiving_queue = Map.delete(receiving_queue, identifier)
          all_frag_data =
            Enum.reduce(num_frags-1..0, [], fn i, acc ->
              frag_data = Map.get(updated_data, i)
              [frag_data | acc]
            end)
          query = :erlang.list_to_binary(List.flatten(all_frag_data))
          {:done, receiving_queue, query}
        else
          receiving_queue = Map.update!(receiving_queue, identifier, fn _ -> current end)
          {:ok, receiving_queue}
        end
      else
        _ ->
          {:error, receiving_queue, "illegal operation, different ip/port"}
      end
    end
  end

  @impl true
  def handle_cast({:fetch_model, query}, ps=%T{}) do
    send_message(ps, ps.ip, ps.port, query)
    {:noreply, ps}
  end

  @impl true
  def handle_cast({:push_tagged_model, query}, ps=%T{}) do
    send_message(ps, ps.ip, ps.port, query)
    {:noreply, ps}
  end

  def get_latest_model(callback_pid, ps, env_filter, strict_match? \\ true) do
    spawn(fn ->
      query = :erlang.term_to_binary({:fetch_model, env_filter, strict_match?, callback_pid})
      :ok = GenServer.cast(ps, {:fetch_model, query})
    end)
  end

  def push_tagged_model(callback_pid, ps, model_tag, updated_model_param) do
    Logger.debug("Push tagged model to server")
    spawn(fn ->
      query = :erlang.term_to_binary({:push_tagged_model, model_tag, updated_model_param, callback_pid})
      :ok = GenServer.cast(ps, {:push_tagged_model, query})
    end)
  end

  def find_model(ps=%T{role: :server}, env_filter, true) do
    index =
      Enum.find_index(ps.models, fn %{tag: model_tag} ->
        model_tag == env_filter
      end)
    if index != nil do
      {:ok, Enum.at(ps.models, index)}
    else
      :not_found
    end
  end

  def process_updated_model_param(ps=%T{role: :server}, env_filter, tagged_model_updates) do
    index =
      Enum.find_index(ps.tagged_model_updates, fn %{tag: model_tag} ->
        model_tag == env_filter
      end)
    all_updates =
      if index != nil do
        List.update_at(ps.tagged_model_updates, index, fn tagged_model ->
          %{updates: updates} = tagged_model
          %{tag: env_filter, updates: [tagged_model_updates | updates]}
        end)
      else
        [%{tag: env_filter, updates: [tagged_model_updates]} | ps.tagged_model_updates]
      end
    %T{ps | tagged_model_updates: all_updates}
  end

  def send_message(ps=%T{}, ip, port, binary, socket \\ nil) do
    frags = pack_message(binary)
    id = Base.encode16(:crypto.hash(:sha256, binary))
    num_frags = Enum.count(frags)
    metainfo = :erlang.term_to_binary(%{metainfo: true, id: id, num_frags: num_frags})
    socket = if socket == nil do
      ps.socket
    else
      socket
    end
    :ok = :gen_udp.send(socket, ip, port, metainfo)
    if num_frags > 1 do
      :timer.sleep(1000)
    end
    Enum.with_index(frags, fn frag, index ->
      binary = :erlang.term_to_binary(%{id: id, frag: frag, index: index, num_frags: num_frags})
      :timer.sleep(2)
      :ok = :gen_udp.send(socket, ip, port, binary)
    end)
    Logger.debug("sent all frags: #{num_frags}")
  end

  def pack_message(binary, pack_size \\ 1500) do
    len = byte_size(binary)
    do_pack_message(binary, len, 0, pack_size, [])
  end

  def do_pack_message(_binary, len, len, _pack_size, acc) do
    Enum.reverse(acc)
  end

  def do_pack_message(binary, len, current_index, pack_size, acc) do
    end_index = current_index + pack_size
    {end_index, length} =
      if end_index >= len do
        {len, len - current_index}
      else
        {end_index, pack_size}
      end
    acc = [:binary.part(binary, current_index, length) | acc]
    do_pack_message(binary, len, end_index, pack_size, acc)
  end
end
