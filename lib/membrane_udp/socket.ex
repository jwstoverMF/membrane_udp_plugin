defmodule Membrane.UDP.Socket do
  @moduledoc false

  @enforce_keys [:port_no, :ip_address]
  defstruct [:port_no, :ip_address, :socket_handle, sock_opts: []]

  @type t :: %__MODULE__{
          port_no: :inet.port_number(),
          ip_address: :inet.socket_address(),
          socket_handle: :gen_udp.socket() | nil,
          sock_opts: [:gen_udp.option()] | nil
        }

  @spec open(socket :: t()) :: {:ok, t()} | {:error, :inet.posix()}
  def open(%__MODULE__{port_no: port_no, ip_address: ip, sock_opts: sock_opts} = socket) do
    open_result = :gen_udp.open(port_no, [:binary, ip: ip, active: true] ++ sock_opts)

    with {:ok, socket_handle} <- open_result,
         # Port may change if 0 is used, ip - when either `:any` or `:loopback` is passed
         {:ok, {real_ip_addr, real_port_no}} <- :inet.sockname(socket_handle) do
        :ok = :inet.setopts(socket_handle, [delay_send: true, sndbuf: 640_000])
      updated_socket = %__MODULE__{
        socket
        | socket_handle: socket_handle,
          port_no: real_port_no,
          ip_address: real_ip_addr
      }

      {:ok, updated_socket}
    end
  end

  @spec close(socket :: t()) :: t()
  def close(%__MODULE__{socket_handle: handle} = socket) when is_port(handle) do
    :gen_udp.close(handle)
    %__MODULE__{socket | socket_handle: nil}
  end

  @spec send(target :: t(), source :: t(), payload :: Membrane.Payload.t()) ::
          :ok | {:error, :not_owner | :inet.posix()}
  def send(
        %__MODULE__{port_no: target_port_no, ip_address: target_ip} = target_sock,
        %__MODULE__{socket_handle: socket_handle} = local_sock,
        payload
      )
      when is_port(socket_handle) do
    :gen_udp.send(socket_handle, target_ip, target_port_no, payload)
    |> case do
      {:error, :eagain} ->
        Process.sleep(50)
        send(target_sock, local_sock, payload)

      resp -> resp
    end
  end
end
