import AppKit
import Darwin
@main struct ThumbnailTests {
static func main() throws {
 var checks=0
 func check(_ value:Bool,_ message:String){checks += 1;precondition(value,message)}
 check(ThumbnailLayout.columns(width:500,cellWidth:156)==3,"Viewport column count")
 check(ThumbnailLayout.columns(width:0,cellWidth:0)==1,"Collapsed viewport safe")
 check(ThumbnailLayout.rows(count:7,columns:3)==3,"Incomplete final row")
 check(ThumbnailLayout.index(column:2,row:1,columns:3,count:7)==5,"Row-major mapping")
 check(ThumbnailLayout.index(column:1,row:2,columns:3,count:7)==nil,"Empty cell not selectable")
 check(ThumbnailLayout.index(column:-1,row:0,columns:3,count:7)==nil,"Negative hit rejected")
 check(ThumbnailLayout.move(2,key:125,columns:3,count:7)==5,"Down one row")
 check(ThumbnailLayout.move(5,key:125,columns:3,count:7)==6,"Short final row clamp")
 check(ThumbnailLayout.move(5,key:126,columns:3,count:7)==2,"Up one row")
 check(ThumbnailLayout.move(0,key:123,columns:3,count:7)==0,"Left edge")
 check(ThumbnailLayout.move(6,key:124,columns:3,count:7)==6,"Right edge")
 check(ThumbnailLayout.move(2,key:119,columns:3,count:7)==6,"End")
 let root=FileManager.default.temporaryDirectory.appendingPathComponent("thumbnail-tests-"+UUID().uuidString)
 try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false);defer{try? FileManager.default.removeItem(at:root)}
 let pixels=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:128,pixelsHigh:64,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
 let png=root.appendingPathComponent("image.png");try pixels.representation(using:.png,properties:[:])!.write(to:png)
 let preview=try ThumbnailDecoder.image(url:png,pixels:32)
 check(preview != nil && max(preview!.size.width,preview!.size.height)<=32,"Actual image downsampled to requested bound")
 let binary=root.appendingPathComponent("binary.png");try Data([0,1,2,3,4]).write(to:binary)
 check(try ThumbnailDecoder.image(url:binary,pixels:128)==nil,"Nonimage content rejected despite extension")
 let sparse=root.appendingPathComponent("large.png");FileManager.default.createFile(atPath:sparse.path,contents:nil)
 let file=try FileHandle(forWritingTo:sparse);try file.truncate(atOffset:ThumbnailDecoder.inputLimit+1);try file.close()
 var rejected=false;do{_=try ThumbnailDecoder.image(url:sparse,pixels:128)}catch{rejected=true};check(rejected,"Oversized input rejected before decoding")
 let fifo=root.appendingPathComponent("fifo.png");precondition(mkfifo(fifo.path,0o600)==0)
 rejected=false;do{_=try ThumbnailDecoder.image(url:fifo,pixels:128)}catch{rejected=true};check(rejected,"FIFO cannot block image preview")
 print("Thumbnails: \(checks) checks passed")
}
}
