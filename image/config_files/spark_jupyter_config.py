import os

c = get_config()  # noqa: F821 - supplied by Jupyter
c.ServerApp.ip = "0.0.0.0"
c.ServerApp.port = int(os.environ["JUPYTER_PORT"])
c.ServerApp.port_retries = 0
c.ServerApp.open_browser = False
c.ServerApp.root_dir = os.environ["ML_DEV_HOME"]
c.IdentityProvider.token = os.environ["JUPYTER_TOKEN"]
# Do not print the login token/URL into docker logs at startup.
c.ServerApp.log_level = "WARN"
