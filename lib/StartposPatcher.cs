// Napoleon MP Europe eight-faction startpos builder. No game data is embedded.
// Reads the user's exact original ABCE file, adds three victory-option records
// derived from that file, and rebases every structural absolute end pointer.
// Original five factions' victory conditions remain byte-for-byte unchanged.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;

public static class NapoleonStartposPatcher {
    public const string OriginalSha256 = "F55B607894CEFD86E62DBF150DB3111B92443919762B2EB6EA2E854C830071D2";
    public const string PatchedSha256 = "043FDA44965EB1A3642A017B298B579161E400690B1F85BBE739F95DA24DDF41";
    public const int OriginalSize = 32333496;
    const int VictoryStart = 733421, VictoryEnd = 736768;
    static readonly int[] PlayableOffsets = {
        727440, 733174, 733334, 737823, 737825, 744529, 744697,
        749677, 755411, 755571, 2632236, 7812948, 7981145
    };
    static readonly Dictionary<byte,int> ScalarSizes = new Dictionary<byte,int> {
        {1,1},{2,1},{3,2},{4,4},{5,8},{6,1},{7,2},{8,4},{9,8},
        {10,4},{11,8},{12,8},{13,12},{16,2}
    };
    sealed class Pointer { public int At, Value; }
    sealed class Record { public int At, End; public string Name; }
    sealed class Scan {
        public byte[] Bytes;
        public int Tail;
        public List<string> Names = new List<string>();
        public List<Pointer> Pointers = new List<Pointer>();
        public List<Record> Targets = new List<Record>();
        public Scan(byte[] bytes) {
            Bytes=bytes;
            if (bytes.Length<20 || U32(bytes,0)!=0xABCE) throw new InvalidDataException("Expected ABCE startpos.");
            Tail=U32(bytes,12);
            if(Tail<16 || Tail>=bytes.Length) throw new InvalidDataException("Invalid ESF footer.");
            int p=Tail, count=U16(bytes,p); p+=2;
            for(int i=0;i<count;i++) {
                int len=U16(bytes,p); p+=2; Need(bytes,p,len);
                Names.Add(Encoding.ASCII.GetString(bytes,p,len)); p+=len;
            }
            if(p!=bytes.Length) throw new InvalidDataException("Unexpected bytes after ESF name table.");
            Walk(16,Tail,0);
        }
        int EndPointer(ref int p,int containingEnd) {
            int at=p, end=U32(Bytes,p); p+=4;
            if(end<p || end>containingEnd) throw new InvalidDataException("Invalid structural end pointer at "+at);
            Pointers.Add(new Pointer {At=at,Value=end}); return end;
        }
        void Walk(int p,int end,int depth) {
            if(depth>100) throw new InvalidDataException("ESF nesting exceeds bound.");
            while(p<end) {
                int at=p; byte tag=Bytes[p++];
                if(tag==0x80 || tag==0x81) {
                    Need(Bytes,p,7); int id=U16(Bytes,p); p+=3;
                    if(id>=Names.Count) throw new InvalidDataException("Invalid node name.");
                    int nodeEnd=EndPointer(ref p,end);
                    string name=Names[id];
                    if(name=="VICTORY_CONDITION_OPTIONS" || name=="CAMPAIGN_PLAYER_SETUP" || name=="FACTION_INFOS")
                        Targets.Add(new Record {At=at,End=nodeEnd,Name=name});
                    if(tag==0x80) Walk(p,nodeEnd,depth+1);
                    else {
                        int count=U32(Bytes,p); p+=4;
                        if(count<0 || count>10000000) throw new InvalidDataException("Invalid record array count.");
                        for(int i=0;i<count;i++) {
                            int itemEnd=EndPointer(ref p,nodeEnd);
                            Walk(p,itemEnd,depth+1); p=itemEnd;
                        }
                        if(p!=nodeEnd) throw new InvalidDataException("Record array size mismatch.");
                    }
                    p=nodeEnd;
                } else if(tag==0x0e || tag==0x0f) {
                    int len=U16(Bytes,p); p+=2;
                    int size=len*(tag==0x0e?2:1); Need(Bytes,p,size);p+=size;
                } else if(ScalarSizes.ContainsKey(tag)) p+=ScalarSizes[tag];
                else if(tag>=0x40 && tag<0x60) p=EndPointer(ref p,end);
                else throw new InvalidDataException("Unsupported ESF tag "+tag.ToString("X2")+" at "+at);
                if(p>end) throw new InvalidDataException("ESF field extends beyond its containing record.");
            }
            if(p!=end) throw new InvalidDataException("ESF record did not finish at its boundary.");
        }
    }
    sealed class Node {
        public byte Tag, Version;
        public ushort Id;
        public byte[] Raw;
        public List<Node> Children;
        public List<List<Node>> Elements;
    }
    static void Need(byte[] bytes,int at,int count) {
        if(at<0 || count<0 || at>bytes.Length-count) throw new InvalidDataException("Truncated ESF.");
    }
    static int U16(byte[] b,int p) { Need(b,p,2);return BitConverter.ToUInt16(b,p); }
    static int U32(byte[] b,int p) {
        Need(b,p,4);uint value=BitConverter.ToUInt32(b,p);
        if(value>Int32.MaxValue) throw new InvalidDataException("ESF offset/count too large.");
        return (int)value;
    }
    static void Put32(byte[] b,int at,int v) { Array.Copy(BitConverter.GetBytes(v),0,b,at,4); }
    static byte[] Slice(byte[] b,int at,int length) { var result=new byte[length];Array.Copy(b,at,result,0,length);return result; }
    static string Sha(byte[] b) { using(var h=SHA256.Create()) return BitConverter.ToString(h.ComputeHash(b)).Replace("-",""); }
    static List<Node> ReadSequence(byte[] b,ref int p,int end) {
        var result=new List<Node>();
        while(p<end) result.Add(ReadNode(b,ref p));
        if(p!=end) throw new InvalidDataException("Victory template boundary mismatch.");
        return result;
    }
    static Node ReadNode(byte[] b,ref int p) {
        int begin=p;byte tag=b[p++];var n=new Node {Tag=tag};
        if(tag==0x80 || tag==0x81) {
            n.Id=(ushort)U16(b,p);p+=2;n.Version=b[p++];int end=U32(b,p);p+=4;
            if(tag==0x80) n.Children=ReadSequence(b,ref p,end);
            else {
                int count=U32(b,p);p+=4;n.Elements=new List<List<Node>>();
                for(int i=0;i<count;i++) { int itemEnd=U32(b,p);p+=4;n.Elements.Add(ReadSequence(b,ref p,itemEnd)); }
                if(p!=end) throw new InvalidDataException("Victory array mismatch.");
            }
        } else {
            if(tag==0x0e || tag==0x0f) {int len=U16(b,p);p+=2+len*(tag==0x0e?2:1);}
            else if(ScalarSizes.ContainsKey(tag)) p+=ScalarSizes[tag];
            else throw new InvalidDataException("Unsupported victory scalar.");
            n.Raw=Slice(b,begin,p-begin);
        }
        return n;
    }
    static void PatchEnd(MemoryStream ms,long position,int origin) {
        long end=ms.Position;ms.Position=position;var b=BitConverter.GetBytes(checked(origin+(int)end));
        ms.Write(b,0,4);ms.Position=end;
    }
    static void WriteNode(BinaryWriter w,Node n,int origin) {
        if(n.Raw!=null) {w.Write(n.Raw);return;}
        w.Write(n.Tag);w.Write(n.Id);w.Write(n.Version);
        long pos=w.BaseStream.Position;w.Write(0);
        if(n.Tag==0x80) foreach(var child in n.Children) WriteNode(w,child,origin);
        else {
            w.Write(n.Elements.Count);
            foreach(var element in n.Elements) {
                long ep=w.BaseStream.Position;w.Write(0);
                foreach(var child in element) WriteNode(w,child,origin);
                PatchEnd((MemoryStream)w.BaseStream,ep,origin);
            }
        }
        PatchEnd((MemoryStream)w.BaseStream,pos,origin);
    }
    static byte[] Write(Node n,int origin) {
        using(var ms=new MemoryStream()) {using(var w=new BinaryWriter(ms)) {WriteNode(w,n,origin);w.Flush();return ms.ToArray();}}
    }
    static Node Clone(Node n) {
        return new Node {Tag=n.Tag,Version=n.Version,Id=n.Id,Raw=n.Raw==null?null:(byte[])n.Raw.Clone(),
            Children=n.Children==null?null:n.Children.Select(Clone).ToList(),
            Elements=n.Elements==null?null:n.Elements.Select(e=>e.Select(Clone).ToList()).ToList()};
    }
    static Node StringNode(string s) {
        byte[] text=Encoding.Unicode.GetBytes(s);var raw=new byte[text.Length+3];raw[0]=0x0e;
        Array.Copy(BitConverter.GetBytes(checked((ushort)s.Length)),0,raw,1,2);Array.Copy(text,0,raw,3,text.Length);
        return new Node {Tag=0x0e,Raw=raw};
    }
    static string Text(Node n) {
        if(n.Tag!=0x0e) throw new InvalidDataException("Expected ESF Unicode string.");
        return Encoding.Unicode.GetString(n.Raw,3,n.Raw.Length-3);
    }
    static Node Named(List<Node> ns,string name,Scan scan) {
        return ns.Single(n=>n.Raw==null && scan.Names[n.Id]==name);
    }
    static void ValidatePlayability(Scan scan) {
        var names=new HashSet<string>(new[]{"france","austria","britain","prussia","russia","sweden","ottomans","spain"});
        var seen=new Dictionary<string,int>();
        foreach(var r in scan.Targets.Where(r=>r.Name=="CAMPAIGN_PLAYER_SETUP")) {
            int p=r.At;Node node=ReadNode(scan.Bytes,ref p);
            var fields=node.Children.Where(n=>n.Raw!=null).ToList();string faction=Text(fields[0]);
            if(names.Contains(faction)) {
                if(fields[2].Tag!=1 || fields[2].Raw[1]!=1) throw new InvalidDataException("Faction remains locked: "+faction);
                if(!seen.ContainsKey(faction)) seen[faction]=0;seen[faction]++;
            }
        }
        if(names.Any(n=>!seen.ContainsKey(n)||seen[n]!=3)) throw new InvalidDataException("Expected three player setups per playable faction.");
        var info=scan.Targets.Single(r=>r.Name=="FACTION_INFOS");int ip=info.At;Node infos=ReadNode(scan.Bytes,ref ip);
        var playable=new HashSet<string>(infos.Elements.Where(e=>e[3].Raw[1]==1).Select(e=>Text(e[0])));
        if(!playable.SetEquals(names)) throw new InvalidDataException("Expected exactly eight playable factions in preopen metadata.");
    }
    public static string Build(string input,string output) {
        if(String.Equals(Path.GetFullPath(input),Path.GetFullPath(output),StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException("Build output must be a separate staged file.");
        byte[] original=File.ReadAllBytes(input);
        if(original.Length!=OriginalSize || Sha(original)!=OriginalSha256)
            throw new InvalidDataException("Unsupported MP Europe startpos SHA256: "+Sha(original));
        var scan=new Scan(original);
        var range=scan.Targets.Single(r=>r.Name=="VICTORY_CONDITION_OPTIONS");
        if(range.At!=VictoryStart || range.End!=VictoryEnd) throw new InvalidDataException("Victory table moved.");
        int p=range.At;Node victory=ReadNode(original,ref p);
        if(victory.Elements.Count!=5 || !Write(victory,range.At).SequenceEqual(Slice(original,range.At,range.End-range.At)))
            throw new InvalidDataException("Victory table did not round-trip byte-identically.");
        List<Node> template=victory.Elements.Single(e=>Text(e[0])=="austria");
        string[] factions={"ottomans","spain","sweden"};
        string[] homes={"eur_rumelia","eur_spain","eur_sweden"};
        for(int i=0;i<factions.Length;i++) {
            var entry=template.Select(Clone).ToList();entry[0]=StringNode(factions[i]);
            Node block=Named(entry,"VICTORY_CONDITIONS_BLOCK",scan);
            if(block.Elements.Count!=3) throw new InvalidDataException("Expected three native victory modes.");
            for(int mode=0;mode<3;mode++) {
                Node condition=Named(block.Elements[mode],"CAMPAIGN_VICTORY_CONDITIONS",scan);
                Node regions=Named(condition.Children,"REGION_KEYS",scan);
                if(mode==1) {
                    if(regions.Elements.Count!=0) throw new InvalidDataException("Conquest template unexpectedly has required regions.");
                } else regions.Elements=new List<List<Node>> {new List<Node> {StringNode(homes[i])}};
            }
            victory.Elements.Add(entry);
        }
        byte[] replacement=Write(victory,VictoryStart);
        // The five original entries retain the same offsets and exact contents.
        if(!replacement.Skip(12).Take(VictoryEnd-VictoryStart-12).SequenceEqual(original.Skip(VictoryStart+12).Take(VictoryEnd-VictoryStart-12)))
            throw new InvalidDataException("Original victory entries changed.");
        int delta=replacement.Length-(VictoryEnd-VictoryStart);
        byte[] modified=(byte[])original.Clone();
        foreach(int offset in PlayableOffsets) {if(modified[offset]!=0) throw new InvalidDataException("Playable flag changed.");modified[offset]=1;}
        if(U32(modified,737827)!=0) throw new InvalidDataException("Sweden list order changed.");Put32(modified,737827,8);
        byte[] result=new byte[modified.Length+delta];
        Array.Copy(modified,0,result,0,VictoryStart);
        Array.Copy(replacement,0,result,VictoryStart,replacement.Length);
        Array.Copy(modified,VictoryEnd,result,VictoryEnd+delta,modified.Length-VictoryEnd);
        foreach(var ptr in scan.Pointers) {
            if(ptr.At>=VictoryStart && ptr.At<VictoryEnd) continue;
            int at=ptr.At>=VictoryEnd?ptr.At+delta:ptr.At;
            Put32(result,at,ptr.Value>=VictoryEnd?ptr.Value+delta:ptr.Value);
        }
        Put32(result,12,scan.Tail+delta);
        var verified=new Scan(result);ValidatePlayability(verified);
        var newRange=verified.Targets.Single(r=>r.Name=="VICTORY_CONDITION_OPTIONS");
        p=newRange.At;Node rebuilt=ReadNode(result,ref p);
        if(rebuilt.Elements.Count!=8 || !Write(rebuilt,newRange.At).SequenceEqual(Slice(result,newRange.At,newRange.End-newRange.At)))
            throw new InvalidDataException("Rebuilt victory table failed structural validation.");
        // Undo only the intended source patches and structural rebase, then
        // reconstruct the exact original to prove unrelated bytes are intact.
        byte[] reverse=new byte[original.Length];
        Array.Copy(result,0,reverse,0,VictoryStart);
        Array.Copy(original,VictoryStart,reverse,VictoryStart,VictoryEnd-VictoryStart);
        Array.Copy(result,VictoryEnd+delta,reverse,VictoryEnd,original.Length-VictoryEnd);
        foreach(var ptr in scan.Pointers) if(ptr.At<VictoryStart || ptr.At>=VictoryEnd) Put32(reverse,ptr.At,ptr.Value);
        Put32(reverse,12,scan.Tail);
        foreach(int offset in PlayableOffsets) reverse[offset]=0;
        Put32(reverse,737827,0);
        if(!reverse.SequenceEqual(original)) throw new InvalidDataException("Unintended ESF byte modification.");
        if(Sha(result)!=PatchedSha256) throw new InvalidDataException("Unexpected rebuilt startpos hash.");
        File.WriteAllBytes(output,result);
        return "Eight-faction MP Europe startpos: "+result.Length+" bytes; "+scan.Pointers.Count+
            " absolute end pointers checked; SHA256 "+Sha(result);
    }
}
