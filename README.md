# scout-inventory-system

## License

This project is licensed under the PolyForm Noncommercial License.
Commercial use is **not permitted**.

See the LICENSE file for details.


## Getting Started

### 1. If you wish to use a Windows-installed browser with WSL, otherwise skip

If you are running **Flutter inside WSL**, Flutter cannot automatically detect **Windows-installed browsers** and may fail with a **“Cannot find Chrome executable”** error. 

To fix this, you must manually tell Flutter which **Chromium-based browser** to use (such as **Brave, Chrome, or Edge**). 

First, determine the Windows path to your browser executable 
(for example, **Brave** is typically located at `C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe`). 

Then, inside WSL, run the following commands to permanently configure Flutter to use that browser: 

set the browser path with `BRAVE="/mnt/c/Program Files/BraveSoftware/Brave-Browser/Application/brave.exe"`,

then export it by running `echo "export CHROME_EXECUTABLE=\"$BRAVE\"" >> ~/.bashrc` and `echo "export CHROME_EXECUTABLE=\"$BRAVE\"" >> ~/.profile`. 

After that, reload your shell using `source ~/.bashrc`, verify the configuration by running `printenv CHROME_EXECUTABLE` (which should output the `/mnt/c/...` path to your browser), and confirm Flutter detects the browser by running `flutter doctor`, where you should see `[✓] Chrome - develop for the web`. 

Run Flutter using the web server device to avoid browser launch issues: `flutter run -d web-server --web-hostname 0.0.0.0 --web-port 45687`, then open the app in Chrome or Edge on Windows at **http://localhost:45687**.
