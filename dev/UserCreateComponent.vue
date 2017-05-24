<template>
    <div>
        <div class="section-title">
            <span>{{gettext('Register new user')}}</span>
            <p class="sub">{{gettext('Here you can register a new wiki user. The user will get a confirmation e-mail with the login data after the registration.')}}</p>
        </div>
    <form>
        <input v-model="userData.firstName" type="text" name="firstName" :placeholder="gettext('First name')">
        <input v-model="userData.lastName" type="text" name="lastName" :placeholder="gettext('Last name')">
        <input v-model="userData.email" type="text" name="email" :placeholder="gettext('Email address')" aria-describedby="emailHelpText">
        <br/>
        <input v-model="userData.loginName" :value="loginName" type="text" name="loginName" :placeholder="gettext('LoginName')" aria-describedby="wikiNameHelpText">
        <input v-model="userData.wikiName" :value="wikiName" type="text" name="wikiName" :placeholder="gettext('WikiName')" aria-describedby="wikiNameHelpText">
        <p class="help-text" id="wikiNameHelpText"><strong>{{gettext("Notice:")}}</strong> <span v-html="getLink()"></span></p>
        <br/>
        <input v-model="generatePassword" id="generatePasswordCheckbox" type ="checkbox">
        <label for="generatePasswordCheckbox" class="checkbox-label">
            {{gettext('Generate password')}}
        </label>
        <div v-show="!generatePassword">
            <input v-model="userData.password" type="password" name="password" :placeholder="gettext('Password')">
            <input v-model="userData.passwordConfirmation" type="password" name="passwordConfirmation" :placeholder="gettext('Confirm password')">
        </div>
        <button type="button" v-on:click="registerUser" class="primary button small pull-right">{{gettext('Register user')}}</button>
    </form>
    </div>
</template>

<script>
var makeToast = function(type, msg) {
    sidebar.makeToast({
        closetime: 5000,
        color: type,
        text: this.gettext(msg)
    });
};
export default {
    data() {
        return {
            generatePassword: false,
            userData: {
                firstName: "",
                lastName: "",
                email: "",
                loginName: "",
                wikiName: "",
                password: "",
                passwordConfirmation: ""
            },
            wikiNameLink: foswiki.getScriptUrl('view') + "/" + foswiki.getPreference("SYSTEMWEB")+ "/WikiName"
        }
    },
    computed: {
        wikiName(){
            var wn = [
                $.wikiword.wikify(this.userData.firstName, {transliterate: true}),
                $.wikiword.wikify(this.userData.lastName, {transliterate: true})
            ].join('');
            this.userData.wikiName = wn;
        },
        loginName(){
            var wn = [
                $.wikiword.wikify(this.userData.firstName, {transliterate: true}),
                $.wikiword.wikify(this.userData.lastName, {transliterate: true})
            ].join('');
            this.userData.loginName = wn;
        },
        isPasswordCorrect(){
            if(this.userData.password !== this.userData.passwordConfirmation){
                return false;
            }

            if(!this.userData.password){
                return false;
            }

            return true;
        }
    },
    methods: {
        getLink() {
            var local_name = this.gettext("unique name");
            return this.gettext("Your name that is visible in Q.wiki. This has to be a [_1].", "<a href='" + this.wikiNameLink + "' target='_blank'>" + local_name + "</a>");
        },
        gettext(text, param) {
            return foswiki.jsi18n.get('UnifiedAuth', text, param);
        },
        registerUser() {
            var self = this;
            let params = {
                loginName: this.userData.loginName,
                wikiName: this.userData.wikiName,
                email: this.userData.email
            }

            if (!params.wikiName || /^\s*$/.test(params.wikiName)) {
                makeToast.call(self, 'alert', 'Field WikiName is required');
                return;
            }

            if (!params.email || /^\s*$/.test(params.wikiName)) {
                makeToast.call(self, 'alert', 'Field email is required');
                return;
            }

            if (!/^(([^<>()\[\]\.,;:\s@\"]+(\.[^<>()\[\]\.,;:\s@\"]+)*)|(\".+\"))@(([^<>()[\]\.,;:\s@\"]+\.)+[^<>()[\]\.,;:\s@\"]{2,})$/i.test(params.email)) {
                makeToast.call(self, 'alert', 'Invalid email address');
                return;
            }

            if (params.loginName == ""){
                params.loginName = this.wikiName;
            }
            if(!this.generatePassword){
                if (!this.userData.password || /^\s*$/.test(this.userData.password)) {
                    makeToast.call(self, 'alert', 'Field password cannot be empty');
                    return;
                };

                if (this.userData.password !== this.userData.passwordConfirmation) {
                    makeToast.call(self, 'alert', 'Password mismatch');
                    return;
                }
                params.password = this.userData.password;
            }

            sidebar.makeModal({type: 'spinner', autoclose: false});
            $.post(foswiki.preferences.SCRIPTURL + "/rest/UnifiedAuthPlugin/registerUser", params)
            .done((result) => {
                makeToast.call(self, 'success', 'Registration successfull');
            }).fail((xhr) => {
                var response = JSON.parse(xhr.responseText);
                makeToast.call(self, 'alert', response.msg);
            }).always(() => sidebar.hideModal());
        }
    },
    created: function() {
        var self = this;
        sidebar.$vm.header = {
            right: [
                {
                    type: 'button',
                    color: 'primary',
                    text: self.gettext('Register user'),
                    callback: function() {self.registerUser();}
                }
            ]
        };
    }
}
</script>
<style lang="sass">
label.checkbox-label{
    padding: 0px 0px 11px 0px;
}
</style>
