package org.cheetah.switchtoubuntu;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.DialogInterface;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;

/**
 * Asks for confirmation, then (as root, through Magisk's su) tells Android's own boot-control HAL
 * to make slot b (Ubuntu) the active slot and reboots. Nothing else is written anywhere.
 */
public class MainActivity extends Activity {
    private final Handler ui = new Handler(Looper.getMainLooper());

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        showConfirm();
    }

    private void showConfirm() {
        new AlertDialog.Builder(this)
                .setTitle(R.string.confirm_title)
                .setMessage(R.string.confirm_msg)
                .setCancelable(false)
                .setPositiveButton(R.string.btn_go, (d, w) -> run(false))
                .setNeutralButton(R.string.btn_test, (d, w) -> run(true))
                .setNegativeButton(R.string.btn_cancel, (d, w) -> finish())
                .show();
    }

    private void run(final boolean dry) {
        final AlertDialog wait = new AlertDialog.Builder(this)
                .setMessage(R.string.working).setCancelable(false).show();
        new Thread(() -> {
            String out;
            int code;
            try {
                String script = readRaw(R.raw.switch_to_ubuntu)
                        .replace("@LIBBC@", getApplicationInfo().nativeLibraryDir + "/libbootctl.so")
                        .replace("@DRY@", dry ? "1" : "0");
                Process p = new ProcessBuilder(findSu(), "-c", script).redirectErrorStream(true).start();
                p.getOutputStream().close();
                out = new String(readAll(p.getInputStream()), StandardCharsets.UTF_8);
                code = p.waitFor();
            } catch (Exception e) {
                out = "su failed: " + e;
                code = 127;
            }
            final String text = out.trim();
            final int rc = code;
            ui.post(() -> {
                wait.dismiss();
                String msg = text.isEmpty() ? "(no output)" : text;
                msg += "\n\nexit code: " + rc;
                if ((rc == 0) == false && (rc < 11 || rc > 17)) msg += "\n\n" + getString(R.string.denied_hint);
                if (rc == 0 && ((dry) == false)) msg += "\n(rebooting)";
                new AlertDialog.Builder(this)
                        .setTitle(R.string.result_title)
                        .setMessage(msg)
                        .setCancelable(false)
                        .setPositiveButton(R.string.btn_ok, (d, w) -> finish())
                        .show();
            });
        }).start();
    }

    private static String findSu() {
        String[] c = {"/system/bin/su", "/debug_ramdisk/su", "/sbin/su", "/system/xbin/su", "/system_ext/bin/su"};
        for (String x : c) if (new java.io.File(x).exists()) return x;
        return "su";
    }

    private String readRaw(int id) throws Exception {
        try (InputStream in = getResources().openRawResource(id)) {
            return new String(readAll(in), StandardCharsets.UTF_8);
        }
    }

    private static byte[] readAll(InputStream in) throws Exception {
        ByteArrayOutputStream bo = new ByteArrayOutputStream();
        byte[] buf = new byte[4096];
        int n;
        while ((n = in.read(buf)) > 0) bo.write(buf, 0, n);
        return bo.toByteArray();
    }
}
