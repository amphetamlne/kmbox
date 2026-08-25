$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
& 'C:\Users\woan\Miniconda3\python.exe' -m pip install pypdf -i https://pypi.tuna.tsinghua.edu.cn/simple --quiet 2>$null
$py = @'
import pypdf
r = pypdf.PdfReader(r"D:\Project\c++\kmbox\tools\tmp\RP2350-USB-A.pdf")
for i, p in enumerate(r.pages):
    print(f"===== PAGE {i+1} =====")
    print(p.extract_text())
'@
$py | & 'C:\Users\woan\Miniconda3\python.exe' -
