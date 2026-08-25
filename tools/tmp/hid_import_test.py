import traceback

try:
    import hid
    print("OK:", getattr(hid, "__file__", "?"))
    print("enumerate:", len(hid.enumerate()))
except Exception:
    traceback.print_exc()
