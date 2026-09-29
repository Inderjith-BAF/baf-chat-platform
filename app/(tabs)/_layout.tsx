import {Tabs} from 'expo-router';
import {Ionicons} from '@expo/vector-icons';
import {colors} from '@/src/theme';
import {Platform} from 'react-native';
export default function TabsLayout(){return <Tabs screenOptions={({route})=>({headerShown:false,tabBarActiveTintColor:colors.blue,tabBarInactiveTintColor:colors.muted,tabBarStyle:{display:Platform.OS==='web'?'none':'flex',height:72,paddingTop:8,paddingBottom:10,backgroundColor:'#FFFFFF',borderTopColor:colors.border},tabBarLabelStyle:{fontWeight:'800',fontSize:11},tabBarIcon:({color,size})=>{const map:any={chats:'chatbubbles',people:'people',activity:'notifications',profile:'person-circle'};return <Ionicons name={map[route.name]} color={color} size={size}/>}})}><Tabs.Screen name="chats" options={{title:'Chats'}}/><Tabs.Screen name="people" options={{title:'People'}}/><Tabs.Screen name="activity" options={{title:'Alerts'}}/><Tabs.Screen name="profile" options={{title:'Me'}}/></Tabs>}
