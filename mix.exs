defmodule LoggerExdatadog.MixProject do
  use Mix.Project

  def project do
    [
      app: :logger_exdatadog,
      version: "1.0.0",
      elixir: "~> 1.14",
      description: description(),
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() != :test,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application() do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps() do
    [
      {:connection, "~> 1.0"},
      {:jason, "~> 1.4", optional: true},
      {:blocking_queue, git: "https://github.com/convo/BlockingQueue.git", tag: "1.4.1", optional: true},
      {:ex_doc, ">= 0.0.0", only: :dev},
      {:credo, ">= 0.0.0", only: :dev}
    ]
  end

  defp description() do
    """
    Formats logs as JSON, forwards to DataDog via TCP or SSL using intake Api, or to console.
    """
  end
end
