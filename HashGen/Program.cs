using System;
using System.Security.Cryptography;

class Program {
    static void Main() {
        var password = "WarpTalk123!";
        var salt = new byte[16];
        using (var rng = RandomNumberGenerator.Create()) {
            rng.GetBytes(salt);
        }
        var hash = Rfc2898DeriveBytes.Pbkdf2(password, salt, 100000, HashAlgorithmName.SHA512, 48);
        var hashStr = $"v2$SHA512$100000$16${Convert.ToBase64String(salt)}${Convert.ToBase64String(hash)}";
        Console.WriteLine(hashStr);
    }
}
