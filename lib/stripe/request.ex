defmodule Stripe.Request do
  @moduledoc """
  A module for working with requests to the Stripe API.
"""

  @max_stripe_pagination_limit 100

  @spec create(String.t, map, map, Keyword.t) :: {:ok, map} | {:error, Stripe.api_error_struct}
  def create(endpoint, changes, schema, opts) do
    changes
    |> Changeset.cast(schema, :create)
    |> Stripe.request(:post, endpoint, %{}, opts)
    |> handle_result
  end

  @doc """
  Specifies an endpoint for the request.

  The endpoint should not include the `v1` prefix or an initial slash, for
  example `put_endpoint(request, "charges")`.

  The endpoint can be a binary or a function which takes the parameters of the
  query and returns an endpoint. The function is not evaluated until just
  before the request is made so the actual parameters can be specified after
  the endpoint.
  """
  @spec put_endpoint(t, String.t()) :: t
  def put_endpoint(%Request{} = request, endpoint) do
    %{request | endpoint: endpoint}
  end

  @doc """
  Specifies a method to use for the request.

  Accepts any of the standard HTTP methods as atoms, that is `:get`, `:post`,
  `:put`, `:patch` or `:delete`.
  """
  @spec put_method(t, Stripe.API.method()) :: t
  def put_method(%Request{} = request, method)
      when method in [:get, :post, :put, :patch, :delete] do
    %{request | method: method}
  end

  @doc """

  Returns %Stripe.List{} of items, using pagination parameters

  ## Example
  retrieve_many(%{limit: 10, starting_after: 3}, "country_specs", []) => {:ok, %Stripe.List{}}

  For more information on pagination parameters read Stripe docs:
  https://stripe.com/docs/api#pagination
  """
  @spec retrieve_many(map, String.t, Keyword.t) :: {:ok, struct} | {:error, Stripe.api_error_struct}
  def retrieve_many(pagination_params, endpoint, opts \\ []) do
    Stripe.request(pagination_params, :get, endpoint, %{}, opts)
    |> handle_result_list(pagination_params, endpoint)
  end

  @doc """
  Returns %Stripe.List{} of all items

  ## Example
  retrieve_all("country_specs") => {:ok, %Stripe.List{}}
  """
  @spec retrieve_all(String.t, Keyword.t) :: {:ok, struct} | {:error, Stripe.api_error_struct}
  def retrieve_all(endpoint, opts \\ []) do
    aggregate_lists(retrieve_many(%{limit: @max_stripe_pagination_limit}, endpoint, opts), [])
  end

  @doc """
  Returns %Stripe.List{} with next set of items, using previously fetched %Stripe.List{}

  ## Example
  {:ok, l} = retrieve_many(%{limit: 10}, "country_specs")
  l |> retrieve_next => {:ok, %Stripe.List{10..20}}
  """
  @spec retrieve_next(Stripe.List.t, Keyword.t) :: {:ok, struct} | {:error, Stripe.api_error_struct}
  def retrieve_next(%Stripe.List{limit: limit, url: url, data: data}, opts \\ []) do
    %{id: starting_after} = List.last(data)
    retrieve_many(%{starting_after: starting_after, limit: limit}, url, opts)
  end

  @spec retrieve_file_upload(String.t, Keyword.t) :: {:ok, struct} | {:error, Stripe.api_error_struct}
  def retrieve_file_upload(endpoint, opts) do
    %{}
    |> Stripe.request_file_upload(:get, endpoint, %{}, opts)
    |> handle_result

  end

  @doc """
  Specify a single param to be included in the request.
  """
  @spec put_param(t, atom, any) :: t
  def put_param(%Request{params: params} = request, key, value) do
    %{request | params: Map.put(params, key, value)}
  end

  @doc """
  Specify that a given set of parameters should be cast to a simple ID.

  Sometimes, it may be convenient to allow end-users to pass in structs (say,
  the card to charge) but the API requires only the ID of the object. This
  function will ensure that before the request is made, the parameters
  specified here will be cast to IDs – if the value of a parameter is a
  struct with an `:id` field, the value of that field will replace the struct
  in the parameter list.

  If the function is called multiple times, the set of parameters to cast to
  ID is merged between the multiple calls.
  """
  @spec cast_to_id(t, [atom]) :: t
  def cast_to_id(%Request{cast_to_id: cast_to_id} = request, new_cast_to_id) do
    %{request | cast_to_id: MapSet.union(cast_to_id, MapSet.new(new_cast_to_id))}
  end


  defp aggregate_lists(response, aggr) do
    case response do
      {:error, error} -> {:error, error}
      {:ok, %{has_more: false, data: data} = list} ->
        {:ok, Map.put(list, :data, Enum.concat(aggr, data))}
      {:ok, %{has_more: true, data: data} = list} ->
        aggregate_lists(retrieve_next(list, []), Enum.concat(aggr, data))
    end
  end

  defp handle_result_list(result, pagination_params, endpoint) do
    with {:ok, handled_result} <- handle_result(result) do
      {:ok, Map.merge(handled_result, %{
        limit: pagination_params.limit,
        url: endpoint
      })}
    else
      {:error, error} -> {:error, error}
    end
  end

  defp handle_result({:ok, result = %{}}), do: {:ok, Converter.stripe_map_to_struct(result)}
  defp handle_result({:error, error}), do: {:error, error}

end
