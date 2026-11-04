#!/usr/bin/env python3
"""Runs native pane integration against disposable local folders, ZIP and localhost FTP."""
import pathlib, subprocess, sys, tempfile, threading, zipfile
from pyftpdlib.authorizers import DummyAuthorizer
from pyftpdlib.handlers import FTPHandler
from pyftpdlib.servers import FTPServer
with tempfile.TemporaryDirectory(prefix='tc-pane-integration-') as tmp:
    root=pathlib.Path(tmp)
    for name in ['local','remote','target']: (root/name).mkdir()
    (root/'local/local.txt').write_text('local bytes')
    (root/'remote/remote.txt').write_text('remote bytes')
    (root/'remote/sub').mkdir(); (root/'remote/sub/nested.txt').write_text('nested remote')
    with zipfile.ZipFile(root/'local/example.zip','w',zipfile.ZIP_DEFLATED) as z:
        z.writestr('inside/archive.txt','archive bytes')
    auth=DummyAuthorizer();auth.add_user('fixture','fixture-password',str(root/'remote'),perm='elradfmwMT')
    class Handler(FTPHandler): pass
    Handler.authorizer=auth
    server=FTPServer(('127.0.0.1',0),Handler)
    thread=threading.Thread(target=server.serve_forever,kwargs={'timeout':.1,'blocking':True,'handle_exit':False},daemon=True);thread.start()
    try: subprocess.run([sys.argv[1],'--provider-smoke-test',str(root),sys.argv[2],str(server.socket.getsockname()[1])],check=True,timeout=90)
    finally:
        server.ioloop.call_later(0,server.close_all)
        thread.join(timeout=2)
