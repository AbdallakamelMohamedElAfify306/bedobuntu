package org.cheetah.roottoggle;

import android.app.Activity;
import android.app.AlertDialog;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;

/**
 * Chooser: Bank Mode (unroot), Root Mode (reroot), or Status.
 * All privileged work goes through Magisk su -c sh.
 */
public class MainActivity extends Activity {
    private final Handler ui = new Handler(Looper.getMainLooper());

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        String action = (getIntent() == null) == false ? getIntent().getAction() : null;
        if ("org.cheetah.roottoggle.UNROOT".equals(action)) {
            confirmUnroot();
            return;
        }
        if ("org.cheetah.roottoggle.REROOT".equals(action)) {
            confirmReroot();
            return;
        }
        showMenu();
    }

    private void showMenu() {
        String[] items = new String[] {
                getString(R.string.bank_name),
                getString(R.string.root_name),
                getString(R.string.status_title),
                getString(R.string.btn_cancel)
        };
        new AlertDialog.Builder(this)
                .setTitle(R.string.app_name)
                .setItems(items, (d, which) -> {
                    if (which == 0) confirmUnroot();
                    else if (which == 1) confirmReroot();
                    else if (which == 2) runStatus();
                    else finish();
                })
                .setOnCancelListener(d -> finish())
                .show();
    }

    private void confirmUnroot() {
        new AlertDialog.Builder(this)
                .setTitle(R.string.confirm_unroot_title)
                .setMessage(R.string.confirm_unroot_msg)
                .setCancelable(false)
                .setPositiveButton(R.string.btn_go, (d, w) -> runScript(R.raw.do_unroot, true))
                .setNegativeButton(R.string.btn_cancel, (d, w) -> finish())
                .show();
    }

    private void confirmReroot() {
        if ((suExists()) == false) {
            showNeedMac();
            return;
        }
        new AlertDialog.Builder(this)
                .setTitle(R.string.confirm_reroot_title)
                .setMessage(R.string.confirm_reroot_msg)
                .setCancelable(false)
                .setPositiveButton(R.string.btn_go, (d, w) -> runScript(R.raw.do_reroot, true))
                .setNegativeButton(R.string.btn_cancel, (d, w) -> finish())
                .show();
    }

    private void showNeedMac() {
        new AlertDialog.Builder(this)
                .setTitle(R.string.need_mac_title)
                .setMessage(R.string.need_mac_msg)
                .setCancelable(false)
                .setPositiveButton(R.string.btn_ok, (d, w) -> finish())
                .show();
    }

    private void runStatus() {
        runScript(R.raw.do_status, false);
    }

    private void runScript(final int rawId, final boolean mayReboot) {
        final AlertDialog wait = new AlertDialog.Builder(this)
                .setMessage(R.string.working).setCancelable(false).show();
        new Thread(() -> {
            String out;
            int code;
            try {
                String script = readRaw(rawId);
                Process p = new ProcessBuilder(findSu(), "-c", script)
                        .redirectErrorStream(true).start();
                p.getOutputStream().close();
                out = new String(readAll(p.getInputStream()), StandardCharsets.UTF_8);
                code = p.waitFor();
            } catch (Exception e) {
                out = "su failed: " + e;
                code = 127;
            }
            final String text = out == null ? "" : out.trim();
            final int rc = code;
            ui.post(() -> {
                try { wait.dismiss(); } catch (Exception ignored) {}
                // If unroot/reroot succeeded the phone reboots; dialog may vanish.
                if (mayReboot && rc == 0) {
                    // Keep a short note; reboot is imminent.
                    return;
                }
                if (rc == 20 || looksLikeNoRoot(text)) {
                    showNeedMac();
                    return;
                }
                String msg = text.isEmpty() ? "(no output)" : text;
                msg += "\n\nexit code: " + rc;
                if ((rc == 0) == false) msg += "\n\n" + getString(R.string.denied_hint);
                new AlertDialog.Builder(this)
                        .setTitle(R.string.result_title)
                        .setMessage(msg)
                        .setCancelable(false)
                        .setPositiveButton(R.string.btn_ok, (d, w) -> finish())
                        .show();
            });
        }).start();
    }

    private static boolean looksLikeNoRoot(String text) {
        if (text == null) return false;
        String t = text.toLowerCase();
        return t.contains("not running as root")
                || t.contains("permission denied")
                || t.contains("su failed");
    }

    private static boolean suExists() {
        String[] c = {
                "/system/bin/su", "/debug_ramdisk/su", "/sbin/su",
                "/system/xbin/su", "/system_ext/bin/su"
        };
        for (String x : c) if (new File(x).exists()) return true;
        // Magisk 31 may still resolve "su" via PATH when live
        try {
            Process p = new ProcessBuilder("sh", "-c", "command -v su").start();
            p.getOutputStream().close();
            byte[] b = readAll(p.getInputStream());
            p.waitFor();
            return b.length > 0;
        } catch (Exception e) {
            return false;
        }
    }

    private static String findSu() {
        String[] c = {
                "/system/bin/su", "/debug_ramdisk/su", "/sbin/su",
                "/system/xbin/su", "/system_ext/bin/su"
        };
        for (String x : c) if (new File(x).exists()) return x;
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
