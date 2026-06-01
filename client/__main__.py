# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------
import asyncio
import os
import sys
import threading

# Before any event loop is created: on Windows, asyncio's Proactor can raise
# ConnectionResetError when the remote closes the connection during transport
# cleanup. Install a policy so every new loop ignores that in its exception handler.
def _make_connection_reset_safe_policy():
    base_policy = asyncio.DefaultEventLoopPolicy()

    class SafePolicy(asyncio.DefaultEventLoopPolicy):
        def new_event_loop(self):
            loop = base_policy.new_event_loop()
            default_handler = loop.default_exception_handler

            def handler(loop, context):
                exc = context.get("exception")
                if isinstance(exc, ConnectionResetError):
                    return
                default_handler(context)

            loop.set_exception_handler(handler)
            return loop

    return SafePolicy()


def _parse_args():
    from client.common import DEFAULT_MODELS, GROQ_TOOL_USE_MODELS
    provider = os.environ.get("LLM_PROVIDER", "openai").strip().lower()
    model_env = {
        "anthropic": "ANTHROPIC_MODEL",
        "groq": "GROQ_MODEL",
        "openai": "OPENAI_MODEL",
    }
    parser = __import__("argparse").ArgumentParser(
        description="rosaOS client: kernel + process manager. Use a local OpenAI-compatible LLM, OpenAI, Groq, or Anthropic.",
    )
    parser.add_argument(
        "--local",
        action="store_true",
        help="Use local OpenAI-compatible endpoint (e.g. vLLM). Else use a hosted API provider.",
    )
    parser.add_argument(
        "--provider",
        choices=("openai", "groq", "anthropic"),
        default=provider if provider in DEFAULT_MODELS else "openai",
        help="Hosted LLM provider when not --local (default: env LLM_PROVIDER or openai).",
    )
    parser.add_argument(
        "--endpoint",
        type=int,
        default=int(os.environ.get("LOCAL_LLM_PORT", "6000")),
        metavar="PORT",
        help="Local LLM port when --local (default: 6000, or env LOCAL_LLM_PORT).",
    )
    parser.add_argument(
        "--anthropic",
        action="store_true",
        help="Use Anthropic API when not --local (legacy shortcut for --provider anthropic).",
    )
    parser.add_argument(
        "--openai",
        action="store_true",
        help="Use OpenAI API when not --local (shortcut for --provider openai).",
    )
    parser.add_argument(
        "--model",
        default=None,
        metavar="MODEL",
        help=(
            "Hosted model when not --local. Defaults by provider: "
            "openai=%s, groq=%s, anthropic=%s. Groq tool-use models: %s."
        )
        % (
            DEFAULT_MODELS["openai"],
            DEFAULT_MODELS["groq"],
            DEFAULT_MODELS["anthropic"],
            ", ".join(GROQ_TOOL_USE_MODELS),
        ),
    )
    parser.add_argument(
        "--port",
        type=int,
        default=int(os.environ.get("RAG_AGENT_PORT", "8765")),
        metavar="PORT",
        help="Client app port (default: 8765, or env RAG_AGENT_PORT).",
    )
    args = parser.parse_args()
    if args.anthropic and args.openai:
        parser.error("--anthropic and --openai are mutually exclusive")
    if args.anthropic:
        args.provider = "anthropic"
    elif args.openai:
        args.provider = "openai"
    if args.model is None:
        args.model = os.environ.get(model_env[args.provider], DEFAULT_MODELS[args.provider])
    return args


if __name__ == "__main__":
    import logging
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
        datefmt="%H:%M:%S",
    )

    args = _parse_args()
    # Set env so common.init_model() and process/kernel use them; worker subprocess inherits env.
    if args.local:
        os.environ["LOCAL_LLM"] = "1"
        os.environ["LOCAL_LLM_PORT"] = str(args.endpoint)
    else:
        os.environ.pop("LOCAL_LLM", None)
        # Select remote provider: OpenAI (default), Groq, or Anthropic.
        if args.provider == "anthropic":
            os.environ["LLM_PROVIDER"] = "anthropic"
            os.environ["ANTHROPIC_MODEL"] = args.model
        elif args.provider == "groq":
            os.environ["LLM_PROVIDER"] = "groq"
            os.environ["GROQ_MODEL"] = args.model
        else:
            os.environ["LLM_PROVIDER"] = "openai"
            os.environ["OPENAI_MODEL"] = args.model
    os.environ["RAG_AGENT_PORT"] = str(args.port)

    from client.common import init_all
    init_all()

    if sys.platform == "win32":
        asyncio.set_event_loop_policy(_make_connection_reset_safe_policy())

    from client.process import start_process_server
    from client.kernel import main_app
    import uvicorn

    threading.Thread(target=start_process_server, daemon=True).start()
    app, port = main_app()
    uvicorn.run(app, port=port)
