// -*- Mode: vala; indent-tabs-mode: nil; tab-width: 4 -*-
/***
    BEGIN LICENSE

    Copyright (C) 2011-2014 elementary Developers

    This program is free software: you can redistribute it and/or modify it
    under the terms of the GNU Lesser General Public License version 3, as published
    by the Free Software Foundation.

    This program is distributed in the hope that it will be useful, but
    WITHOUT ANY WARRANTY; without even the implied warranties of
    MERCHANTABILITY, SATISFACTORY QUALITY, or FITNESS FOR A PARTICULAR
    PURPOSE.  See the GNU General Public License for more details.

    You should have received a copy of the GNU General Public License along
    with this program.  If not, see <http://www.gnu.org/licenses/>

    END LICENSE
***/

public enum PromptType {
    /**
     * Reply with the password.
     */
    SECRET,
    /**
     * Reply with the password.
     */
    QUESTION,
    /**
     * Reply with any text to confirm that you want to login.
     */
    CONFIRM_LOGIN,
    /**
     * Show fingerprint prompt
     */
    FPRINT
}

public enum PromptText {
    /**
     * A message asking for username entry
     */
    USERNAME,
    /**
     * A message asking for password entry
     */
    PASSWORD,
    /**
     * The message was not in the expected list
     */
    OTHER
}

public enum MessageText {
    /**
     * fprintd message to swipe finger
     */
    FPRINT_SWIPE,
    /**
     * fprintd message to swipe again
     */
    FPRINT_SWIPE_AGAIN,
    /**
     * fprintd message to swipe longer
     */
    FPRINT_SWIPE_TOO_SHORT,
    /**
     * fprintd message to center finger
     */
    FPRINT_NOT_CENTERED,
    /**
     * fprintd message to remove finger
     */
    FPRINT_REMOVE,
    /**
     * fprintd message to place finger on device again
     */
    FPRINT_PLACE,
    /**
     * fprintd message to place finger on device again
     */
    FPRINT_PLACE_AGAIN,
    /**
     * fprintd failure message
     */
    FPRINT_NO_MATCH,
    /**
     * fprintd timeout message
     */
    FPRINT_TIMEOUT,
    /**
     * Unknown fprintd error
     */ 
    FPRINT_ERROR,
    /**
     * Login failed
     */ 
    FAILED,
    /**
     * The message was not in the expected list
     */
    OTHER
}

/**
 * A LoginMask is for example a UI such as the LoginBox that communicates with
 * the user.
 * It forms with the LoginGateway a protocol for logging in users. The steps
 * are roughly:
 * 1. gateway.login_with_mask - Call this as soon as you know the username
 *           The gateway will get the login_name via the property of your
 *           mask.
 * 2. mask.show_prompt or mask.show_message - one of both is called and the
 *           mask has to display that to the user.
 *           show_prompt also demands that you answer
 *           via gateway.respond.
 * 3. Repeat Step 2 until the gateway fires login_successful
 * 4. Call gateway.start_session after login_successful is called
 *
 *
 */
public interface LoginMask : GLib.Object {

    public abstract string login_name { get; }
    public abstract string login_session { get; }

    /**
     * Present a prompt to the user. The interface can answer via the
     * respond method of the LoginGateway.
     */
     public abstract void show_prompt (PromptType type, PromptText prompttext = PromptText.OTHER, string text = "");
     
     public abstract void show_message (LightDM.MessageType type, MessageText messagetext = MessageText.OTHER, string text = "");

     public abstract void not_authenticated ();

    /**
     * The login-try was aborted because another LoginMask wants to login.
     */
    public abstract void login_aborted ();
}


public interface LoginGateway : GLib.Object {

    public abstract bool hide_users { get; }
    public abstract bool has_guest_account { get; }
    public abstract bool show_manual_login { get; }
    public abstract bool lock { get; }
    public abstract string default_session { get; }
    public abstract string? select_user { get; }

    /**
     * Starts the login-procedure for the passed
     */
    public abstract void login_with_mask (LoginMask mask, bool guest);

    public abstract void respond (string message);

    /**
     * Called when a user successfully logins. It gives the Greeter time
     * to run fade out animations etc.
     * The Gateway shall not accept any request from now on beside
     * the start_session call.
     */
    public signal void login_successful ();

    /**
     * Only to be called after the login_successful was fired.
     * Will start the session and exits this process.
     */
    public abstract void start_session ();

}

/**
 * Passes communication to LightDM.
 */
public class LightDMGateway : LoginGateway, Object {

    /**
     * The last Authenticatable that tried to login via this authenticator.
     * This variable is null in case no one has tried to login so far.
     */
    LoginMask? current_login { get; private set; default = null; }

    /**
     * True if and only if the current login got at least one prompt.
     * This is for example used for the guest login which doesn't need
     * to answer any prompt and can directly login. Here we first have to
     * ask the LoginMask for a confirmation or otherwise you would
     * automatically login as guest if you select the guest login.
     */
    bool had_prompt = false;

    /**
     * True if and only if we first await a extra-response before
     * we actually login. In case another login_with_mask call happens
     * we just set this to false again.
     */
    bool awaiting_confirmation = false;

    bool awaiting_start_session = false;

    LightDM.Greeter lightdm;

    public bool hide_users {
        get {
            return lightdm.hide_users_hint;
        }
    }
    public bool has_guest_account {
        get {
            return lightdm.has_guest_account_hint;
        }
    }
    public bool show_manual_login {
        get {
            return lightdm.show_manual_login_hint;
        }
    }
    public bool lock {
        get {
            return lightdm.lock_hint;
        }
    }
    public string default_session {
        get {
            return lightdm.default_session_hint;
        }
    }
    public string? select_user { 
        get {
            return lightdm.select_user_hint;
        }
    }

    public LightDMGateway () {
        message ("Connecting to LightDM...");
        lightdm = new LightDM.Greeter ();

        try {
            lightdm.connect_to_daemon_sync ();
        } catch (Error e) {
            warning (@"Couldn't connect to lightdm: $(e.message)");
            Posix.exit (Posix.EXIT_FAILURE);
        }
        message ("Successfully connected to LightDM.");
        lightdm.show_message.connect (show_message);
        lightdm.show_prompt.connect (show_prompt);
        lightdm.authentication_complete.connect (authentication);
    }

    public void login_with_mask (LoginMask login, bool guest) {
        if (awaiting_start_session) {
            warning ("Got login_with_mask while awaiting start_session!");
            return;
        }

        message (@"Starting authentication...");
        if (current_login != null)
            current_login.login_aborted ();

        had_prompt = false;
        awaiting_confirmation = false;

        current_login = login;
        if (guest) {
            lightdm.authenticate_as_guest ();
        } else {
            lightdm.authenticate (current_login.login_name);
        }
    }

    public void respond (string text) {
        if (awaiting_start_session) {
            warning ("Got respond while awaiting start_session!");
            return;
        }

        if (awaiting_confirmation) {
            warning ("Got user-interaction. Starting session");
            awaiting_start_session = true;
            login_successful ();
        } else {
            // We don't log this as it contains passwords etc.
            lightdm.respond (text);
        }
    }

    void show_message (string text, LightDM.MessageType type) {
        message (@"LightDM message: '$text' ($(type.to_string ()))");
        
        var messagetext = string_to_messagetext(text);
        
        if (messagetext == MessageText.FPRINT_SWIPE || messagetext == MessageText.FPRINT_PLACE) {
            // For the fprint module, there is no prompt message from PAM.
            send_prompt (PromptType.FPRINT);
        }  
        
        current_login.show_message (type, messagetext, text);
    }

    void show_prompt (string text, LightDM.PromptType type) {
        message (@"LightDM prompt: '$text' ($(type.to_string ()))");
        
        send_prompt (lightdm_prompttype_to_prompttype(type), string_to_prompttext(text), text);
    }
    
    void send_prompt (PromptType type, PromptText prompttext = PromptText.OTHER, string text = "") {
        had_prompt = true;

        current_login.show_prompt (type, prompttext, text);
    }

    PromptType lightdm_prompttype_to_prompttype(LightDM.PromptType type) {
        if (type == LightDM.PromptType.SECRET) {
            return PromptType.SECRET;
        }
        
        return PromptType.QUESTION;
    }
    
    PromptText string_to_prompttext (string text) {
        if (text == "Password: ") {
            return PromptText.PASSWORD;
        }
        
        if (text == "login: ") {
            return PromptText.USERNAME;
        }
        
        return PromptText.OTHER;
    }
    
    MessageText string_to_messagetext (string text) {
        // Ideally this would query PAM and ask which module is currently active,
        // but since we're running through LightDM we don't have that ability.
        // There should at be a state machine to transition to and from the 
        // active module depending on the messages recieved. But, this is can go
        // wrong quickly. 
        // The reason why this is needed is, for example, we can get the "An
        // unknown error occured" message from pam_fprintd, but we can get it 
        // from some other random module as well. You never know.
        // Maybe it's worth adding some LightDM/PAM functionality for this? 
        // The PAM "feature" which makes it all tricky is that modules can send 
        // arbitrary messages to the stream and it's hard to analyze or keep track
        // of them programmatically. 
        // Also, there doesn't seem to be a way to give the user a choice over
        // which module he wants to use to authenticate (ie. maybe today I have
        // a bandaid over my finger and I can't scan it so I have to wait for it
        // time out, if I didn't disable that in the settings)
        
        // These messages are taken from here: 
        //  - https://cgit.freedesktop.org/libfprint/fprintd/tree/pam/fingerprint-strings.h
        //  - https://cgit.freedesktop.org/libfprint/fprintd/tree/pam/pam_fprintd.c
        
        if (text == GLib.dgettext("fprintd","An unknown error occured")) {
            // LIGHTDM_MESSAGE_TYPE_ERROR
            return MessageText.FPRINT_ERROR;
        } else if (check_fprintd_string(text, "Swipe", "across")) {
            // LIGHTDM_MESSAGE_TYPE_INFO
            return MessageText.FPRINT_SWIPE;
        } else if (text == GLib.dgettext("fprintd", "Swipe your finger again")) {
            // LIGHTDM_MESSAGE_TYPE_ERROR
            return MessageText.FPRINT_SWIPE_AGAIN;
        } else if (text == GLib.dgettext("fprintd", "Swipe was too short, try again")) {
            // LIGHTDM_MESSAGE_TYPE_ERROR
            return MessageText.FPRINT_SWIPE_TOO_SHORT;
        } else if (text == GLib.dgettext("fprintd", "Your finger was not centered, try swiping your finger again")) {
            // LIGHTDM_MESSAGE_TYPE_ERROR
            return MessageText.FPRINT_NOT_CENTERED;
        } else if (text == GLib.dgettext("fprintd", "Remove your finger, and try swiping your finger again")) {
            // LIGHTDM_MESSAGE_TYPE_ERROR
            return MessageText.FPRINT_REMOVE;
        } else if (check_fprintd_string(text, "Place", "on")) {
            // LIGHTDM_MESSAGE_TYPE_INFO
            return MessageText.FPRINT_PLACE;
        } else if (text == GLib.dgettext("fprintd", "Place your finger on the reader again")) {
            // LIGHTDM_MESSAGE_TYPE_ERROR
            return MessageText.FPRINT_PLACE_AGAIN;
        } else if (text == GLib.dgettext("fprintd", "Failed to match fingerprint")) {
            // LIGHTDM_MESSAGE_TYPE_ERROR
            return MessageText.FPRINT_NO_MATCH;
        } else if (text == GLib.dgettext("fprintd", "Verification timed out")) {
            // LIGHTDM_MESSAGE_TYPE_INFO
            return MessageText.FPRINT_TIMEOUT;
        } else if (text == "Login failed") {
            return MessageText.FAILED;
        } 

        return MessageText.OTHER;
    }
    
    public bool check_fprintd_string(string text, string action, string position) {
        string[] fingers = {"finger",
                        "left thumb", "left index finger", "left middle finger", "left ring finger", "left little finger",
                        "right thumb", "right index finger", "right middle finger", "right ring finger", "right little finger"};
                        
        foreach (var finger in fingers) {
            var english_string = action.concat(" your ", finger, " ", position, " %s");
            
            // load translations from the fprintd domain
            if (text.has_prefix (GLib.dgettext ("fprintd", english_string).printf (""))) {
                return true;
            }

        }
        
        return false;
    }

    public void start_session () {
        if (!awaiting_start_session) {
            warning ("Got start_session without awaiting it.");
        }
        message (@"Starting session $(current_login.login_session)");
        PantheonGreeter.instance.set_greeter_state ("last-user",
                                            current_login.login_name);
        try {
            lightdm.start_session_sync (current_login.login_session);
        } catch (Error e) {
            error (e.message);
        }
    }

    void authentication () {
        if (lightdm.is_authenticated) {
            // Check if the LoginMask actually got userinput that confirms
            // that the user wants to start a session now.
            if (had_prompt) {
                // If yes, start a session
                awaiting_start_session = true;
                login_successful ();
            } else {
                message ("Auth complete, but we await user-interaction before we"
                        + "start a session");
                // If no, send a prompt and await the confirmation via respond.
                // This variables is checked in respond as a special case.
                awaiting_confirmation = true;
                current_login.show_prompt (PromptType.CONFIRM_LOGIN);
            }
        } else {
            current_login.not_authenticated ();
        }
    }
}


/**
 * For testing purposes a Gateway which only allows the guest to login.
 */
public class DummyGateway : LoginGateway, Object {

    public bool hide_users { get { return false; } }
    public bool has_guest_account { get { return true; } }
    public bool show_manual_login { get { return true; } }
    public bool lock { get {return false; } }
    public string default_session { get { return ""; } }
    public string? select_user { get { return null; } }

    LoginMask last_login_mask;

    bool last_was_guest = true;

    public void login_with_mask (LoginMask mask, bool guest) {
        if (last_login_mask != null)
            mask.login_aborted ();

        last_was_guest = guest;
        last_login_mask = mask;
        Idle.add (() => {
            mask.show_prompt (guest ? PromptType.CONFIRM_LOGIN : PromptType.SECRET, guest ? PromptText.OTHER : PromptText.PASSWORD);
            return false;
        });
    }

    public void respond (string message) {
        if (last_was_guest) {
            Idle.add (() => {
                login_successful ();
                return false;
            });
        } else {
            Idle.add (() => {
                last_login_mask.not_authenticated ();
                return false;
            });
        }
    }

    public void start_session () {
        message ("Started session");
        Posix.exit (Posix.EXIT_SUCCESS);
    }

}
