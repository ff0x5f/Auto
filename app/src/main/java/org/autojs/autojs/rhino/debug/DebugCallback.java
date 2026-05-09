package org.autojs.autojs.rhino.debug;

import org.mozilla.javascript.tools.debugger.Dim;

public interface DebugCallback {

    /**
     * Called when the source text of some script has been changed.
     */
    void updateSourceText(Dim.SourceInfo sourceInfo);

    /**
     * Called when the interrupt loop has been entered.
     */
    void enterInterrupt(Dim.StackFrame lastFrame,
                        String threadTitle,
                        String alertMessage);

}
