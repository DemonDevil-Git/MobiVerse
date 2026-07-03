namespace MobiVerse.Core;

internal static class ImageDimensions
{
    public static (int Width, int Height) Read(string path)
    {
        using var stream = File.OpenRead(path);
        using var reader = new BinaryReader(stream);
        if (stream.Length >= 24)
        {
            var header = reader.ReadBytes(24);
            if (header.AsSpan(0, 8).SequenceEqual(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 }))
                return (ReadBigEndian(header, 16), ReadBigEndian(header, 20));
            if (header[0] == 'G' && header[1] == 'I' && header[2] == 'F')
                return (header[6] | header[7] << 8, header[8] | header[9] << 8);
        }
        stream.Position = 0;
        if (reader.ReadByte() != 0xFF || reader.ReadByte() != 0xD8) return (1200, 1800);
        while (stream.Position + 4 < stream.Length)
        {
            if (reader.ReadByte() != 0xFF) continue;
            var marker = reader.ReadByte();
            while (marker == 0xFF) marker = reader.ReadByte();
            if (marker is 0xD8 or 0xD9) continue;
            var length = ReadUInt16BigEndian(reader);
            if (length < 2) break;
            if (marker is >= 0xC0 and <= 0xC3 or >= 0xC5 and <= 0xC7 or >= 0xC9 and <= 0xCB or >= 0xCD and <= 0xCF)
            {
                _ = reader.ReadByte();
                var height = ReadUInt16BigEndian(reader);
                var width = ReadUInt16BigEndian(reader);
                return (width, height);
            }
            stream.Seek(length - 2, SeekOrigin.Current);
        }
        return (1200, 1800);
    }

    private static int ReadBigEndian(byte[] bytes, int offset) =>
        bytes[offset] << 24 | bytes[offset + 1] << 16 | bytes[offset + 2] << 8 | bytes[offset + 3];

    private static int ReadUInt16BigEndian(BinaryReader reader) => reader.ReadByte() << 8 | reader.ReadByte();
}
