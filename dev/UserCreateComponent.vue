<template>
    <div>
        <h1 class="primary">{{gettext('Register new user')}}</h1>
        <p>{{gettext('Here you can register a new wiki user. The user will get a confirmation e-mail with the login data after the registration.')}}</p>
    <form>
        <input v-model="userData.firstName" type="text" name="firstName" :placeholder="gettext('First name')">
        <input v-model="userData.lastName" type="text" name="lastName" :placeholder="gettext('Last name')">
        <input v-model="userData.email" type="text" name="email" :placeholder="gettext('Email address')" aria-describedby="emailHelpText">
        <p class="help-text" id="emailHelpText"><strong>{{gettext('Notice:')}}</strong> {{gettext('Your Email address will not be published.')}}</p>
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
            this.userData.wikiName = $.wikiword.wikify(this.userData.firstName + this.userData.lastName, {transliterate: true});
        },
        loginName(){
            this.userData.loginName = $.wikiword.wikify(this.userData.firstName + this.userData.lastName, {transliterate: true});
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
            let params = {
                loginName: this.userData.loginName,
                wikiName: this.userData.wikiName,
                email: this.userData.email
            }
            if (params.loginName == ""){
                params.loginName = this.wikiName;
            }
            if(!this.generatePassword){
                params.password = this.userData.password;
            }
            $.post(foswiki.preferences.SCRIPTURL + "/rest/UnifiedAuthPlugin/registerUser", params)
            .done((result) => {
                sidebar.makeToast({
                    closetime: 2000,
                    color: "success",
                    text: "Registration successfull"
                });
            })
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
