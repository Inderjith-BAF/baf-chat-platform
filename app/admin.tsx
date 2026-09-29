import {useEffect,useState} from 'react';
import {LinearGradient} from 'expo-linear-gradient';
import {Pressable,ScrollView,StyleSheet,Text,View} from 'react-native';
import {router} from 'expo-router';
import {colors,shadow} from '@/src/theme';
import {supabase} from '@/src/lib/supabase';

type Channel={id:string;name:string;slug:string;emoji:string};
type Member={user_id:string;role:'admin'|'member';profile:any;access:string[]};

export default function Admin(){
 const[workspaceId,setWorkspaceId]=useState<string|null>(null);
 const[members,setMembers]=useState<Member[]>([]);
 const[requests,setRequests]=useState<any[]>([]);
 const[channels,setChannels]=useState<Channel[]>([]);
 const[requestRoles,setRequestRoles]=useState<Record<string,'admin'|'member'>>({});
 const[requestAccess,setRequestAccess]=useState<Record<string,string[]>>({});
 const[allowed,setAllowed]=useState<boolean|null>(null);
 const[error,setError]=useState('');
 const[busy,setBusy]=useState<string|null>(null);

 const load=async()=>{
  const{data:{user}}=await supabase.auth.getUser();
  if(!user){router.replace('/login');return}
  const wm=await supabase.from('workspace_members').select('workspace_id,role').eq('user_id',user.id).eq('status','active').limit(1).maybeSingle();
  if(!wm.data||wm.data.role!=='admin'){setAllowed(false);return}
  setAllowed(true);setWorkspaceId(wm.data.workspace_id);
  const[cr,mr,rr,ar]=await Promise.all([
   supabase.from('channels').select('id,name,slug,emoji').eq('workspace_id',wm.data.workspace_id).order('created_at'),
   supabase.from('workspace_members').select('user_id,role,profile:profiles(id,full_name,email,avatar_url,status)').eq('workspace_id',wm.data.workspace_id).eq('status','active'),
   supabase.from('join_requests').select('id,user_id,email,requested_name,status,created_at').eq('workspace_id',wm.data.workspace_id).eq('status','pending').order('created_at',{ascending:false}),
   supabase.from('channel_members').select('channel_id,user_id')
  ]);
  if(cr.error) setError(cr.error.message); else setChannels(cr.data||[]);
  if(mr.error)setError(mr.error.message);
  if(rr.error)setError(rr.error.message);
  if(ar.error)setError(ar.error.message);
  const accessByUser:Record<string,string[]>={};
  (ar.data||[]).forEach((x:any)=>{(accessByUser[x.user_id]??=[]).push(x.channel_id)});
  setMembers((mr.data||[]).map((m:any)=>({...m,access:accessByUser[m.user_id]||[]})));
  const pending=rr.data||[];
  setRequests(pending);
  const defaults=channelsForRequests(cr.data||[]);
  setRequestRoles(Object.fromEntries(pending.map((r:any)=>[r.id,'member'])));
  setRequestAccess(Object.fromEntries(pending.map((r:any)=>[r.id,defaults])));
 };
 const channelsForRequests=(list:Channel[])=>list.map(c=>c.id);

 useEffect(()=>{load()},[]);

 const toggle=(ids:string[],id:string)=>ids.includes(id)?ids.filter(x=>x!==id):[...ids,id];

 const approve=async(r:any)=>{
  if(!workspaceId)return;
  setBusy(r.id);setError('');
  const role=requestRoles[r.id]||'member';
  const access=requestAccess[r.id]||[];
  const ins=await supabase.from('workspace_members').upsert({workspace_id:workspaceId,user_id:r.user_id,role,status:'active'});
  if(ins.error){setError(ins.error.message);setBusy(null);return}
  await supabase.from('channel_members').delete().eq('user_id',r.user_id).in('channel_id',channels.map(c=>c.id));
  if(access.length){
   const rows=access.map(channel_id=>({channel_id,user_id:r.user_id}));
   const ac=await supabase.from('channel_members').upsert(rows);
   if(ac.error){setError(ac.error.message);setBusy(null);return}
  }
  const jr=await supabase.from('join_requests').update({status:'approved',reviewed_at:new Date().toISOString()}).eq('id',r.id);
  if(jr.error){setError(jr.error.message);setBusy(null);return}
  setBusy(null);load();
 };

 const updateMember=async(m:Member)=>{
  if(!workspaceId)return;
  setBusy(m.user_id);setError('');
  const up=await supabase.from('workspace_members').update({role:m.role}).eq('workspace_id',workspaceId).eq('user_id',m.user_id);
  if(up.error){setError(up.error.message);setBusy(null);return}
  await supabase.from('channel_members').delete().eq('user_id',m.user_id).in('channel_id',channels.map(c=>c.id));
  if(m.access.length){
   const ac=await supabase.from('channel_members').upsert(m.access.map(channel_id=>({channel_id,user_id:m.user_id})));
   if(ac.error){setError(ac.error.message);setBusy(null);return}
  }
  setBusy(null);load();
 };

 const setMember=(userId:string,patch:Partial<Member>)=>setMembers(prev=>prev.map(m=>m.user_id===userId?{...m,...patch}:m));

 if(allowed===false)return <View style={s.center}><Text style={s.big}>🔒</Text><Text style={s.title}>Admin access required</Text><Text style={s.sub}>Only workspace admins can manage members.</Text><Pressable onPress={()=>router.back()} style={s.primary}><Text style={s.primaryText}>Back to chat</Text></Pressable></View>;
 if(allowed===null)return <View style={s.center}><Text style={s.sub}>Loading workspace controls…</Text></View>;

 return <View style={s.root}>
  <View style={s.head}><Pressable onPress={()=>router.back()} style={s.back}><Text>←</Text></Pressable><View><Text style={s.kicker}>WORKSPACE ADMIN</Text><Text style={s.title}>Manage the crew ⚡</Text></View><View style={s.adminPill}><Text style={s.adminPillText}>ADMIN</Text></View></View>
  <ScrollView contentContainerStyle={s.content}>
   <LinearGradient colors={['#EAF9FF','#F5EEFF']} style={s.hero}><Text style={s.heroEmoji}>🫶</Text><View style={{flex:1}}><Text style={s.heroTitle}>Bookairfreight HQ</Text><Text style={s.heroSub}>Approve people, assign roles, and control which channels each teammate can access.</Text></View></LinearGradient>
   <View style={s.actions}><Pressable onPress={()=>router.push('/signup')} style={s.secondary}><Text style={s.secondaryText}>Share signup</Text></Pressable></View>
   {error?<Text style={s.error}>{error}</Text>:null}

   <Text style={s.section}>PENDING REQUESTS · {requests.length}</Text>
   {requests.length===0?<View style={s.empty}><Text style={s.emptyTitle}>No pending requests</Text><Text style={s.emptyText}>New signups will appear here for approval.</Text></View>:requests.map(r=>{
    const role=requestRoles[r.id]||'member'; const access=requestAccess[r.id]||[];
    return <View key={r.id} style={s.requestCard}>
     <View style={s.memberTop}><View style={s.avatar}><Text style={s.avatarText}>{r.requested_name.trim().split(/\s+/).map((x:string)=>x[0]).join('').slice(0,2).toUpperCase()}</Text></View><View style={{flex:1}}><Text style={s.memberName}>{r.requested_name}</Text><Text style={s.email}>{r.email}</Text></View></View>
     <Text style={s.controlLabel}>ROLE</Text><View style={s.chips}><Pressable onPress={()=>setRequestRoles(x=>({...x,[r.id]:'member'}))} style={[s.chip,role==='member'&&s.chipActive]}><Text style={[s.chipText,role==='member'&&s.chipTextActive]}>Member</Text></Pressable><Pressable onPress={()=>setRequestRoles(x=>({...x,[r.id]:'admin'}))} style={[s.chip,role==='admin'&&s.chipActivePink]}><Text style={[s.chipText,role==='admin'&&s.chipTextActive]}>Admin</Text></Pressable></View>
     <Text style={s.controlLabel}>CHANNEL ACCESS · {access.length}/{channels.length}</Text><View style={s.chips}>{channels.map(c=><Pressable key={c.id} onPress={()=>setRequestAccess(x=>({...x,[r.id]:toggle(access,c.id)}))} style={[s.channelChip,access.includes(c.id)&&s.channelActive]}><Text style={s.channelEmoji}>{c.emoji}</Text><Text style={[s.chipText,access.includes(c.id)&&s.chipTextActive]}>{c.name}</Text></Pressable>)}</View>
     <Pressable disabled={busy===r.id} onPress={()=>approve(r)} style={s.approve}><Text style={s.approveText}>{busy===r.id?'Saving…':'Approve & grant access'}</Text></Pressable>
    </View>
   })}

   <Text style={s.section}>ACTIVE MEMBERS · {members.length}</Text>
   {members.map(m=><View key={m.user_id} style={s.activeCard}>
    <View style={s.memberTop}><View style={s.avatar}><Text style={s.avatarText}>{m.profile.full_name.trim().split(/\s+/).map((x:string)=>x[0]).join('').slice(0,2).toUpperCase()}</Text></View><View style={{flex:1}}><Text style={s.memberName}>{m.profile.full_name}</Text><Text style={s.email}>{m.profile.email||'No email'}</Text></View></View>
    <Text style={s.controlLabel}>ROLE</Text><View style={s.chips}><Pressable onPress={()=>setMember(m.user_id,{role:'member'})} style={[s.chip,m.role==='member'&&s.chipActive]}><Text style={[s.chipText,m.role==='member'&&s.chipTextActive]}>Member</Text></Pressable><Pressable onPress={()=>setMember(m.user_id,{role:'admin'})} style={[s.chip,m.role==='admin'&&s.chipActivePink]}><Text style={[s.chipText,m.role==='admin'&&s.chipTextActive]}>Admin</Text></Pressable></View>
    <Text style={s.controlLabel}>CHANNEL ACCESS · {m.access.length}/{channels.length}</Text><View style={s.chips}>{channels.map(c=><Pressable key={c.id} onPress={()=>setMember(m.user_id,{access:toggle(m.access,c.id)})} style={[s.channelChip,m.access.includes(c.id)&&s.channelActive]}><Text style={s.channelEmoji}>{c.emoji}</Text><Text style={[s.chipText,m.access.includes(c.id)&&s.chipTextActive]}>{c.name}</Text></Pressable>)}</View>
    <Pressable disabled={busy===m.user_id} onPress={()=>updateMember(m)} style={s.save}><Text style={s.saveText}>{busy===m.user_id?'Saving…':'Save member access'}</Text></Pressable>
   </View>)}
  </ScrollView>
 </View>
}

const s=StyleSheet.create({
 root:{flex:1,backgroundColor:colors.bg},center:{flex:1,justifyContent:'center',alignItems:'center',padding:25,backgroundColor:colors.bg},big:{fontSize:42},head:{padding:22,paddingTop:28,flexDirection:'row',alignItems:'center',gap:12,borderBottomWidth:1,borderBottomColor:colors.border,backgroundColor:'#fff'},back:{width:38,height:38,borderRadius:13,backgroundColor:'#F1F6FF',alignItems:'center',justifyContent:'center'},kicker:{fontSize:8,fontWeight:'900',letterSpacing:2.5,color:colors.cyan},title:{fontSize:24,fontWeight:'900',color:colors.ink,marginTop:3},sub:{fontSize:12,color:colors.muted,marginTop:7,textAlign:'center'},adminPill:{marginLeft:'auto',backgroundColor:colors.pink,paddingHorizontal:10,paddingVertical:6,borderRadius:10},adminPillText:{fontSize:8,fontWeight:'900',color:colors.ink},content:{width:'100%',maxWidth:980,alignSelf:'center',padding:22,paddingBottom:60},hero:{padding:20,borderRadius:22,flexDirection:'row',alignItems:'center',gap:14},heroEmoji:{fontSize:34},heroTitle:{fontSize:17,fontWeight:'900',color:colors.ink},heroSub:{fontSize:11,color:colors.muted,marginTop:4,lineHeight:17},actions:{flexDirection:'row',gap:10,marginTop:16},secondary:{height:46,borderRadius:14,paddingHorizontal:18,backgroundColor:'#fff',borderWidth:1,borderColor:colors.border,alignItems:'center',justifyContent:'center'},secondaryText:{fontSize:11,fontWeight:'900',color:colors.blue},section:{fontSize:9,fontWeight:'900',letterSpacing:2.5,color:colors.blue,marginTop:24,marginBottom:9},requestCard:{padding:17,borderRadius:20,backgroundColor:'#fff',borderWidth:1,borderColor:'#D8E6F2',marginBottom:10,...shadow},activeCard:{padding:17,borderRadius:20,backgroundColor:'#fff',borderWidth:1,borderColor:colors.border,marginBottom:10},memberTop:{flexDirection:'row',alignItems:'center',gap:12},avatar:{width:44,height:44,borderRadius:14,backgroundColor:'#DDEBFF',alignItems:'center',justifyContent:'center'},avatarText:{fontSize:12,fontWeight:'900',color:colors.blue},memberName:{fontSize:12,fontWeight:'900',color:colors.ink},email:{fontSize:9,color:colors.muted,marginTop:3},controlLabel:{fontSize:8,fontWeight:'900',letterSpacing:1.6,color:'#8A9AAD',marginTop:15,marginBottom:7},chips:{flexDirection:'row',flexWrap:'wrap',gap:7},chip:{paddingHorizontal:12,paddingVertical:8,borderRadius:11,backgroundColor:'#F1F4F8',borderWidth:1,borderColor:'#E1E8EF'},chipActive:{backgroundColor:'#E8ECFF',borderColor:'#BFC7FF'},chipActivePink:{backgroundColor:'#FCE8F1',borderColor:'#F2B7D0'},chipText:{fontSize:9,fontWeight:'900',color:'#66768A'},chipTextActive:{color:colors.ink},channelChip:{paddingHorizontal:10,paddingVertical:8,borderRadius:11,backgroundColor:'#F7F9FB',borderWidth:1,borderColor:'#E1E8EF',flexDirection:'row',alignItems:'center',gap:5},channelActive:{backgroundColor:'#EAF8FF',borderColor:'#B9E7F5'},channelEmoji:{fontSize:11},approve:{height:44,borderRadius:13,backgroundColor:colors.blue,alignItems:'center',justifyContent:'center',marginTop:17},approveText:{fontSize:10,fontWeight:'900',color:'#fff'},save:{height:42,borderRadius:12,backgroundColor:'#F1F6FF',borderWidth:1,borderColor:'#D6E3F0',alignItems:'center',justifyContent:'center',marginTop:17},saveText:{fontSize:10,fontWeight:'900',color:colors.blue},empty:{padding:18,borderRadius:17,backgroundColor:'#fff',borderWidth:1,borderColor:colors.border},emptyTitle:{fontSize:12,fontWeight:'900',color:colors.ink},emptyText:{fontSize:10,color:colors.muted,marginTop:4},primary:{marginTop:18,height:46,borderRadius:14,paddingHorizontal:18,backgroundColor:colors.blue,alignItems:'center',justifyContent:'center'},primaryText:{fontSize:11,fontWeight:'900',color:'#fff'},error:{fontSize:10,color:'#C94A75',marginTop:10}
});