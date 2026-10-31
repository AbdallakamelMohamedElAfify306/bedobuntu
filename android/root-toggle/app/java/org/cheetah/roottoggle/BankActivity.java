package org.cheetah.roottoggle;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;

/** Launcher alias target: opens MainActivity in UNROOT mode. */
public class BankActivity extends Activity {
    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        Intent i = new Intent(this, MainActivity.class);
        i.setAction("org.cheetah.roottoggle.UNROOT");
        i.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP);
        startActivity(i);
        finish();
    }
}
