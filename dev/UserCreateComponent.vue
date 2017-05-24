<template>
    <div>
        <h1 class="primary">{{maketext('Register new user')}}</h1>
        <p>{{maketext('Here you can register a new wiki user. The user will get a confirmation e-mail with the login data after the registration.')}}</p>
    <form>
        <input v-model="userData.firstName" type="text" name="firstName" :placeholder="maketext('First name')">
        <input v-model="userData.lastName" type="text" name="lastName" :placeholder="maketext('Last name')">
        <input v-model="userData.email" type="text" name="email" :placeholder="maketext('Email address')" aria-describedby="emailHelpText">
        <p class="help-text" id="emailHelpText"><strong>{{maketext('Notice:')}}</strong> {{maketext('Your Email address will not be published.')}}</p>
        <br/>
        <template v-if="propsData.showUserLoginName">
            <input v-model="userData.loginName" :value="loginName" type="text" name="loginName" :placeholder="maketext('LoginName')" aria-describedby="wikiNameHelpText">
        </template>
        <input v-model="userData.wikiName" :value="wikiName" type="text" name="wikiName" :placeholder="maketext('WikiName')" aria-describedby="wikiNameHelpText">
        <p class="help-text" id="wikiNameHelpText"><strong>{{maketext("Notice:")}}</strong> <span v-html="getLink()"></span></p>
        <br/>
        <input v-model="generatePassword" id="generatePasswordCheckbox" type ="checkbox">
        <label for="generatePasswordCheckbox" class="checkbox-label">
            {{maketext('Generate password')}}
        </label>
        <div v-show="!generatePassword">
            <input v-model="userData.password" type="password" name="password" :placeholder="maketext('Password')">
            <input v-model="userData.passwordConfirmation" type="password" name="passwordConfirmation" :placeholder="maketext('Confirm password')">
        </div>
        <button type="button" v-on:click="registerUser" class="primary button small pull-right">{{maketext('Register user')}}</button>
    </form>
    </div>
</template>

<script>
/*global $ */
import MaketextMixin from './MaketextMixin.vue'

export default {
    mixins: [MaketextMixin],
    props: ['propsData'],
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
            var local_name = this.maketext("unique name");
            return this.maketext("Your name that is visible in Q.wiki. This has to be a [_1].", ["<a href='" + this.wikiNameLink + "' target='_blank'>" + local_name + "</a>"]);
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
                    text: self.maketext('Register user'),
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
