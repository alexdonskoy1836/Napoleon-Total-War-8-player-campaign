using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using System.Security.Cryptography;

public static class Napoleon8Tools {
    public static string Hash(byte[] data) {
        using (var sha = SHA256.Create()) return BitConverter.ToString(sha.ComputeHash(data)).Replace("-", "").ToLowerInvariant();
    }
    public static void RequireHash(byte[] data, string expected, string label) {
        var actual = Hash(data);
        if (!String.Equals(actual, expected, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException(label + " is not the supported file. SHA256: " + actual);
    }
    public static byte[] Patch(byte[] input, int[] offsets, byte[] before, byte[] after) {
        if (offsets.Length != before.Length || offsets.Length != after.Length) throw new InvalidDataException("Invalid patch lengths");
        var result = (byte[])input.Clone();
        for (int i = 0; i < offsets.Length; i++) {
            if (offsets[i] < 0 || offsets[i] >= result.Length || result[offsets[i]] != before[i])
                throw new InvalidDataException("Patch signature mismatch at " + offsets[i].ToString("X"));
            result[offsets[i]] = after[i];
        }
        return result;
    }
    public static byte[] ReadPackEntry(string path, string wanted) {
        using (var stream = File.OpenRead(path)) using (var reader = new BinaryReader(stream)) {
            if (Encoding.ASCII.GetString(reader.ReadBytes(4)) != "PFH0") throw new InvalidDataException("Expected PFH0 pack: " + path);
            uint flags = reader.ReadUInt32();
            uint dependencies = reader.ReadUInt32();
            uint dependencyBytes = reader.ReadUInt32();
            uint count = reader.ReadUInt32();
            uint indexBytes = reader.ReadUInt32();
            if (flags > 4 || dependencies > 10000 || count > 1000000 || indexBytes > 100000000 || dependencyBytes > 10000000)
                throw new InvalidDataException("Unsupported PFH0 header");
            long indexStart = 24L + dependencyBytes;
            long dataStart = indexStart + indexBytes;
            if (dataStart > stream.Length) throw new InvalidDataException("Truncated pack index");
            stream.Position = indexStart;
            long dataOffset = dataStart;
            long foundOffset = -1; int foundSize = 0;
            for (uint i = 0; i < count; i++) {
                uint size = reader.ReadUInt32();
                var nameBytes = new List<byte>();
                byte b;
                while ((b = reader.ReadByte()) != 0) {
                    if (stream.Position > dataStart || nameBytes.Count >= 4096) throw new InvalidDataException("Invalid pack path");
                    nameBytes.Add(b);
                }
                string name = Encoding.GetEncoding(1252).GetString(nameBytes.ToArray());
                if (String.Equals(name, wanted, StringComparison.OrdinalIgnoreCase)) {
                    if (foundOffset >= 0 || size > 10000000) throw new InvalidDataException("Duplicate or oversized requested entry");
                    foundOffset = dataOffset; foundSize = (int)size;
                }
                dataOffset = checked(dataOffset + size);
            }
            if (stream.Position != dataStart || dataOffset != stream.Length) throw new InvalidDataException("PFH0 index/file length mismatch");
            if (foundOffset < 0) throw new FileNotFoundException("Pack entry not found: " + wanted);
            stream.Position = foundOffset;
            byte[] result = reader.ReadBytes(foundSize);
            if (result.Length != foundSize) throw new EndOfStreamException();
            return result;
        }
    }
    public static byte[] MoviePack(string[] names, byte[][] contents) {
        if (names.Length != contents.Length || names.Length == 0) throw new InvalidDataException("Invalid pack contents");
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        using (var indexStream = new MemoryStream()) using (var index = new BinaryWriter(indexStream)) {
            for (int i = 0; i < names.Length; i++) {
                if (!seen.Add(names[i]) || names[i].Contains("..") || names[i].Contains("/") || names[i].IndexOf('\0') >= 0)
                    throw new InvalidDataException("Invalid pack entry name");
                index.Write(contents[i].Length);
                index.Write(Encoding.ASCII.GetBytes(names[i])); index.Write((byte)0);
            }
            using (var output = new MemoryStream()) using (var writer = new BinaryWriter(output)) {
                writer.Write(Encoding.ASCII.GetBytes("PFH0"));
                writer.Write(4); writer.Write(0); writer.Write(0);
                writer.Write(names.Length); writer.Write((int)indexStream.Length);
                writer.Write(indexStream.ToArray());
                foreach (byte[] content in contents) writer.Write(content);
                return output.ToArray();
            }
        }
    }
}
