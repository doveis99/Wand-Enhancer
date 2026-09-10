using System;
using System.IO;
using System.Linq;
using WandEnhancer.Core;
using WandEnhancer.Core.Js;
using WandEnhancer.Models;

internal static class Program
{
    private static string Apply(string source, bool expected = true)
    {
        var patch = EnhancerConfig.GetInstance()[EPatchType.ActivatePro]
            .Single(entry => entry.Name == "setAccountReducer");
        var result = new JavaScriptPatchApplier((message, type) => { })
            .Apply("app-test.bundle.js", source, patch, EPatchType.ActivatePro, out bool applied);
        if (applied != expected || patch.Applied != expected)
            throw new Exception("Incorrect patch completion state");
        return result;
    }

    private static void Reject(string body)
    {
        try { Apply("const m=\"ACTION_SET_ACCOUNT\";" + body); }
        catch (Exception ex) when (ex.Message.Contains("version may not be supported")) { return; }
        throw new Exception("Unsupported reducer was accepted: " + body);
    }

    private static void Main(string[] args)
    {
        const string original = "const m=\"ACTION_SET_ACCOUNT\";function p(t,$e){return{...t,account:$e}}";
        string patched = Apply(original);
        if (patched == original || Apply(patched) != patched)
            throw new Exception("Reducer must patch once and remain byte-identical on reapplication");
        string spaced = patched.Replace("account:", "account : ").Replace("=>", " => ")
            .Replace("&&", " && ").Replace("==", " == ").Replace("{", "{\n  ").Replace("}", "\n}");
        if (Apply(spaced) != spaced) throw new Exception("Formatted payload not recognized");
        Apply("function unrelated(){return 1}", false);
        Reject("function p(t,e){return{...t,account:transform(e)}}");
        Reject("function p(t,e){return{...t,account:e.account}}");
        Reject("function p(t,e){return{...t,otheraccount:e}}");
        Reject("const unsupported=1;");
        Reject(patched.Substring(patched.IndexOf("function", StringComparison.Ordinal))
            .Replace("active", "inactive"));

        string outDir = Path.GetFullPath(".tmp/account-reducer/results");
        Directory.CreateDirectory(outDir);
        File.WriteAllText(Path.Combine(outDir, "behavior.js"), patched + @"
const assert = require('node:assert/strict');
const state = {other: 42};
const account = {id: 'user', subscription: null};
const result = p(state, account);
assert.equal(result.other, 42);
assert.equal(result.account.id, 'user');
assert.equal(result.account.subscription.state, 'active');
assert.equal(account.subscription, null);
for (const value of [null, undefined, false, 0, '']) assert.equal(p(state,value).account, value);
console.log('PASS reducer behavior and input immutability');
");
        foreach (string path in args)
        {
            string source = File.ReadAllText(path);
            string result = Apply(source);
            if (Apply(result) != result) throw new Exception("Real bundle reapplication changed the reducer");
            File.WriteAllText(Path.Combine(outDir, Path.GetFileName(path)), result);
            Console.WriteLine("PASS bundle: " + path);
        }
        Console.WriteLine("PASS account reducer regression cases");
    }
}
